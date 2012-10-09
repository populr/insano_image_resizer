require 'yaml'
require 'shellwords'
require 'exifr'

module InsanoImageResizer
  class Processor

    include Configurable
    include Shell
    include Loggable

    def initialize(options = {vips_path: "vips"})
      @vips_path = options[:vips_path]
    end

    def process(input_path, viewport_size = {}, interest_point = {}, quality = 60)
      input_properties = fetch_image_properties(input_path)
      input_has_alpha = (input_properties[:bands] == 4)

      output_tmp = Tempfile.new(["img", input_has_alpha ? ".png" : ".jpg"])

      transform = calculate_transform(input_path, input_properties, viewport_size, interest_point)
      run_transform(input_path, output_tmp.path, transform, quality)

      return output_tmp.path
    end

    def fetch_image_properties(input_path)
      # read in the image headers to discover the width and height of the image.
      # There's actually some extra metadata we ignore here, but this seems to be
      # the only way to get width and height from VIPS.
      result = {}
      result[:w] = run("#{@vips_path} im_header_int Xsize '#{input_path}'").to_f
      result[:h] = run("#{@vips_path} im_header_int Ysize '#{input_path}'").to_f
      result[:bands] = run("#{@vips_path} im_header_int Bands '#{input_path}'").to_f
      return result
    end

    def calculate_transform(input_path, input_properties, viewport_size, interest_point)

      # By default, the interest size is 30% of the total image size.
      # In the future, this could be a parameter, and you'd pass the # of pixels around
      # the POI you are interested in.
      if (interest_point[:xf])
        interest_point[:x] = input_properties[:w] * interest_point[:xf]
      end

      if (interest_point[:yf])
        interest_point[:y] = input_properties[:h] * interest_point[:yf]
      end

      if (interest_point[:region] == nil)
        interest_point[:region] = 1
      end

      if (interest_point[:x] == nil)
        interest_point[:x] = input_properties[:w] * 0.5
        interest_point[:region] = 1
      end
      if (interest_point[:y] == nil)
        interest_point[:y] = input_properties[:h] * 0.5
        interest_point[:region] = 1
      end

      interest_size = {w: input_properties[:w] * interest_point[:region], h: input_properties[:h] * interest_point[:region]}

      # Has the user specified both the width and the height of the viewport? If they haven't,
      # let's go ahead and fill in the missing properties for them so that they get output at
      # the original aspect ratio of the image.
      if ((viewport_size[:w] == nil) && (viewport_size[:h] == nil))
        viewport_size = {w: input_properties[:w], h: input_properties[:h]}

      elsif (viewport_size[:w] == nil)
        viewport_size[:w] = (viewport_size[:h] * (input_properties[:w].to_f / input_properties[:h].to_f))

      elsif (viewport_size[:h] == nil)
        viewport_size[:h] = (viewport_size[:w] * (input_properties[:h].to_f / input_properties[:w].to_f))
      end

      # how can we take our current image and fit it into the viewport? Time for
      # some fun math! First, let's determine a scale such that the image fits
      # within the viewport. There are a few rules we want to apply:
      # 1) The image should _always_ fill the viewport.
      # 2) The 1/3 of the image around the interest_point should always be visible.
      #    This means that if we try to cram a massive image into a tiny viewport,
      #    we won't get a simple scale-to-fill. We'll get a more zoomed-in version
      #    showing just the 1/3 around the interest_point.

      scale_to_fill = [viewport_size[:w] / input_properties[:w].to_f, viewport_size[:h] / input_properties[:h].to_f].max
      scale_to_interest = [interest_size[:w] / input_properties[:w].to_f, interest_size[:h] / input_properties[:h].to_f].max

      log.debug("POI: ")
      log.debug(interest_point)
      log.debug("Image properties: ")
      log.debug(input_properties)
      log.debug("Requested viewport size: ")
      log.debug(viewport_size)
      log.debug("scale_to_fill: %f" % scale_to_fill)
      log.debug("scale_to_interest: %f" % scale_to_interest)


      scale_for_best_region = [scale_to_fill, scale_to_interest].max

      # cool! Now, let's figure out what the content offset within the image should be.
      # We want to keep the point of interest in view whenever possible. First, let's
      # compute an optimal frame around the POI:
      best_region = {x: interest_point[:x].to_f - (input_properties[:w].to_f * scale_for_best_region) / 2,
                     y: interest_point[:y].to_f - (input_properties[:h].to_f * scale_for_best_region) / 2,
                     w: input_properties[:w].to_f * scale_for_best_region,
                     h: input_properties[:h].to_f * scale_for_best_region}

      # Up to this point, we've been using 'scale_for_best_region' to be the preferred scale of the image.
      # So, scale could be 1/3 if we want to show the area around the POI, or 1 if we're fitting a whole image
      # in a viewport that is exactly the same aspect ratio.

      # The next step is to compute a scale that should be applied to the image to make this desired section of
      # the image fit within the viewport. This is different from the previous scale—if we wanted to fit 1/3 of
      # the image in a 100x100 pixel viewport, we computed best_region using that 1/3, and now we need to find
      # the scale that will fit it into 100px.
      scale = [scale_to_fill, viewport_size[:w].to_f / best_region[:w], viewport_size[:h].to_f / best_region[:h]].max

      # Next, we scale the best_region so that it is in final coordinates. When we perform the affine transform,
      # it will SCALE the entire image and then CROP it to a region, so our transform rect needs to be in the
      # coordinate space of the SCALED image, not the initial image.
      transform = {}
      transform[:x] = best_region[:x] * scale
      transform[:y] = best_region[:y] * scale
      transform[:w] = best_region[:w] * scale
      transform[:h] = best_region[:h] * scale
      transform[:scale] = scale

      # transform now represents the region we'd like to have in the final image. All of it, or part of it, may
      # not actually be within the bounds of the image! We're about to apply some constraints, but first let's
      # trim the best_region so that it's the SHAPE of the viewport, not just the SCALE of the viewport. Remember,
      # since the region is still centered around the POI, we can just trim equally on either the W or H as necessary.
      transform[:x] -= (viewport_size[:w] - transform[:w]) / 2
      transform[:y] -= (viewport_size[:h] - transform[:h]) / 2
      transform[:w] = viewport_size[:w]
      transform[:h] = viewport_size[:h]

      transform[:x] = transform[:x].round
      transform[:y] = transform[:y].round

      # alright—now our transform most likely extends beyond the bounds of the image
      # data. Let's add some constraints that push it within the bounds of the image.
      if (transform[:x] + transform[:w] > input_properties[:w].to_f * scale)
        transform[:x] = input_properties[:w].to_f * scale - transform[:w]
      end

      if (transform[:y] + transform[:h] > input_properties[:h].to_f * scale)
        transform[:y] = input_properties[:h].to_f * scale - transform[:h]
      end

      if (transform[:x] < 0)
        transform[:x] = 0.0
      end

      if (transform[:y] < 0)
        transform[:y] = 0.0
      end

      log.debug("The transform properties:")
      log.debug(transform)

      return transform
    end

    def run_transform(input_path, output_path, transform, quality = 90)
      # Call through to VIPS:
      # int im_affinei(in, out, interpolate, a, b, c, d, dx, dy, x, y, w, h)
      # The first six params are a transformation matrix. A and D are used for X and Y
      # scale, the other two are b = Y skew and c = X skew.  TX and TY are translations
      # but don't seem to be used.
      # The last four params define a rect of the source image that is transformed.
      output_extension = output_path[-3..-1]
      quality_extension = ""

      if (output_extension == "jpg")
        quality_extension = ":#{quality}"
      end

      if (transform[:scale] < 0.5)
        # If we're shrinking the image by more than a factor of two, let's do a two-pass operation. The reason we do this
        # is that the interpolators, such as bilinear and bicubic, don't produce very good results when scaling an image
        # by more than 1/2. Instead, we use a high-speed shrinking function to reduce the image by the smallest integer scale
        # greater than the desired scale, and then go the rest of the way with an interpolated affine transform.
        shrink_factor = (1.0 / transform[:scale]).floor

        # To ensure that we actually do both passes, don't let the im_shrink go all the way. This will result in terrible
        # looking shrunken images, since im_shrink basically just cuts pixels out.
        if (shrink_factor == 1.0 / transform[:scale])
          shrink_factor -= 1
        end

        transform[:scale] *= shrink_factor

        if (input_path[-4..-3] != ".")
          FileUtils.mv(input_path, input_path+"."+output_extension)
          input_path = input_path + "." + output_extension
        end
        intermediate_path = input_path[0..-4]+"_shrunk." + output_extension

        run("#{@vips_path} im_shrink '#{input_path}' '#{intermediate_path}#{quality_extension}' #{shrink_factor} #{shrink_factor}")
        run("#{@vips_path} im_affine '#{intermediate_path}' '#{output_path}#{quality_extension}' #{transform[:scale]} 0 0 #{transform[:scale]} 0 0 #{transform[:x]} #{transform[:y]} #{transform[:w]} #{transform[:h]}")
        FileUtils.rm(intermediate_path)

      else
        run("#{@vips_path} im_affine '#{input_path}' '#{output_path}#{quality_extension}' #{transform[:scale]} 0 0 #{transform[:scale]} 0 0 #{transform[:x]} #{transform[:y]} #{transform[:w]} #{transform[:h]}")
      end

      # find the EXIF values
      orientation = 0
      if input_path[-3..-1] == 'jpg'
        orientation = EXIFR::JPEG.new(input_path).orientation.to_i
      end
      log.debug('Orientation flag: ' + orientation.to_s)

      if orientation == 3 || orientation == 6 || orientation == 8
        FileUtils.mv(output_path, intermediate_path)
        o_transform = []
        if orientation == 3
          run("#{@vips_path} im_rot180 '#{intermediate_path}' '#{output_path}#{quality_extension}'")
        elsif orientation == 6
          run("#{@vips_path} im_rot90 '#{intermediate_path}' '#{output_path}#{quality_extension}'")
        elsif orientation == 8
          run("#{@vips_path} im_rot270 '#{intermediate_path}' '#{output_path}#{quality_extension}'")
        end
        FileUtils.rm(intermediate_path)
        run("mogrify -strip #{output_path}")
      end

      FileUtils.rm(input_path)
      return output_path
    end
  end
end

