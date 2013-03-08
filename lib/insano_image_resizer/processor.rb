require 'yaml'
require 'exifr'
require 'cocaine'

module InsanoImageResizer
  class Processor

    include Configurable
    include Loggable
    include Cocaine

    DEFAULT_QUALITY_LIMITS = { :min_area => { :area => 4000, :quality => 90 },
                               :max_area => { :area => 1000000, :quality => 60 }}

    def initialize(options = {})
      @vips_path = options[:vips_path] || 'vips'
      @identify_path = options[:identify_path] || 'identify'
    end

    def process(input_path, viewport_size = {}, interest_point = {}, quality_limits=DEFAULT_QUALITY_LIMITS)
      width, height, original_format, target_extension = fetch_image_properties(input_path)

      exif_result = handle_exif_rotation(input_path, original_format)
      width, height = [height, width] if exif_result == :swap_dimensions

      output_tmp = Tempfile.new(['img', ".#{target_extension}"])

      transform = calculate_transform(input_path, width, height, viewport_size, interest_point)
      quality = target_jpg_quality(transform[:w], transform[:h], quality_limits) if target_extension == 'jpg'
      run_transform(input_path, output_tmp.path, transform, original_format, target_extension, quality)

      output_tmp.path
    end

    # limits is of the form:
    # { :min_area => { :area => 4000, :quality => 90 },
    #   :max_area => { :area => 1000000, :quality => 60 }}
    def target_jpg_quality(width, height, limits)
      return limits.to_i unless limits.is_a?(Hash)
      min_area = limits[:min_area][:area]
      min_area_quality = limits[:min_area][:quality]
      max_area = limits[:max_area][:area]
      max_area_quality = limits[:max_area][:quality]
      normalized_target_area = [width * height - min_area, 0].max
      normalized_max_area =  max_area - min_area
      target_area_fraction = [normalized_target_area.to_f / normalized_max_area, 1].min
      quality_span = min_area_quality - max_area_quality
      quality_fraction = quality_span * target_area_fraction
      min_area_quality - quality_fraction
    end

    private

    def fetch_image_properties(input_path)
      line = Cocaine::CommandLine.new(@identify_path, '-format "%w %h %m" :input')
      width, height, original_format = line.run(:input => input_path).split(' ')

      target_extension = (original_format == 'PNG' ? 'png' : 'jpg')
      [width.to_i, height.to_i, original_format, target_extension]
    end

    def calculate_transform(input_path, width, height, viewport_size, interest_point)

      # By default, the interest size is 30% of the total image size.
      # In the future, this could be a parameter, and you'd pass the # of pixels around
      # the POI you are interested in.
      if (interest_point[:xf])
        interest_point[:x] = width * interest_point[:xf]
      end

      if (interest_point[:yf])
        interest_point[:y] = height * interest_point[:yf]
      end

      if (interest_point[:region] == nil)
        interest_point[:region] = 1
      end

      if (interest_point[:x] == nil)
        interest_point[:x] = width * 0.5
        interest_point[:region] = 1
      end
      if (interest_point[:y] == nil)
        interest_point[:y] = height * 0.5
        interest_point[:region] = 1
      end

      interest_size = {w: width * interest_point[:region], h: height * interest_point[:region]}

      # Has the user specified both the width and the height of the viewport? If they haven't,
      # let's go ahead and fill in the missing properties for them so that they get output at
      # the original aspect ratio of the image.
      if ((viewport_size[:w] == nil) && (viewport_size[:h] == nil))
        viewport_size = {w: width, h: height}

      elsif (viewport_size[:w] == nil)
        viewport_size[:w] = (viewport_size[:h] * (width.to_f / height.to_f))

      elsif (viewport_size[:h] == nil)
        viewport_size[:h] = (viewport_size[:w] * (height.to_f / width.to_f))
      end

      # how can we take our current image and fit it into the viewport? Time for
      # some fun math! First, let's determine a scale such that the image fits
      # within the viewport. There are a few rules we want to apply:
      # 1) The image should _always_ fill the viewport.
      # 2) The 1/3 of the image around the interest_point should always be visible.
      #    This means that if we try to cram a massive image into a tiny viewport,
      #    we won't get a simple scale-to-fill. We'll get a more zoomed-in version
      #    showing just the 1/3 around the interest_point.

      scale_to_fill = [viewport_size[:w] / width.to_f, viewport_size[:h] / height.to_f].max
      scale_to_interest = [interest_size[:w] / width.to_f, interest_size[:h] / height.to_f].max

      scale_for_best_region = [scale_to_fill, scale_to_interest].max

      # cool! Now, let's figure out what the content offset within the image should be.
      # We want to keep the point of interest in view whenever possible. First, let's
      # compute an optimal frame around the POI:
      best_region = {x: interest_point[:x].to_f - (width.to_f * scale_for_best_region) / 2,
                     y: interest_point[:y].to_f - (height.to_f * scale_for_best_region) / 2,
                     w: width.to_f * scale_for_best_region,
                     h: height.to_f * scale_for_best_region}

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
      if (transform[:x] + transform[:w] > width.to_f * scale)
        transform[:x] = width.to_f * scale - transform[:w]
      end

      if (transform[:y] + transform[:h] > height.to_f * scale)
        transform[:y] = height.to_f * scale - transform[:h]
      end

      if (transform[:x] < 0)
        transform[:x] = 0.0
      end

      if (transform[:y] < 0)
        transform[:y] = 0.0
      end

      transform
    end

    def run_transform(input_path, output_path, transform, original_format, output_extension, quality)
      # Call through to VIPS:
      # int im_affinei(in, out, interpolate, a, b, c, d, dx, dy, x, y, w, h)
      # The first six params are a transformation matrix. A and D are used for X and Y
      # scale, the other two are b = Y skew and c = X skew.  TX and TY are translations
      # but don't seem to be used.
      # The last four params define a rect of the source image that is transformed.

      quality_extension = quality ? ":#{quality}" : ''

      if (transform[:scale] < 0.5)
        # If we're shrinking the image by more than a factor of two, let's do a two-pass operation. The reason we do this
        # is that the interpolators, such as bilinear and bicubic, don't produce very good results when scaling an image
        # by more than 1/2. Instead, we use a high-speed shrinking function to reduce the image by the smallest integer scale
        # greater than the desired scale, and then go the rest of the way with an interpolated affine transform.
        shrink_factor = (1.0 / transform[:scale]).floor

        # To ensure that we actually do both passes, don't let the im_shrink go all the way. This will result in terrible
        # looking shrunken images, since im_shrink basically just cuts pixels out.
        shrink_factor -= 1 if shrink_factor == 1.0 / transform[:scale]

        transform[:scale] *= shrink_factor


        intermediate_path = "#{input_path}_shrunk.#{output_extension}"
        intermediate_quality_extension = quality ? ":90" : ''


        line = Cocaine::CommandLine.new(@vips_path, "im_shrink :input :intermediate_path :shrink_factor :shrink_factor")
        line.run(:input => input_path,
                 :intermediate_path => "#{intermediate_path}#{intermediate_quality_extension}",
                 :shrink_factor => shrink_factor.to_s)


        line = Cocaine::CommandLine.new(@vips_path, "im_affine :intermediate_path :output :scale 0 0 :scale 0 0 :x :y :w :h")
        line.run(:output => "#{output_path}#{quality_extension}",
                 :intermediate_path => intermediate_path,
                 :scale => transform[:scale].to_s,
                 :x => transform[:x].to_s,
                 :y => transform[:y].to_s,
                 :w => transform[:w].to_s,
                 :h => transform[:h].to_s)

        FileUtils.rm(intermediate_path)

      else
        line = Cocaine::CommandLine.new(@vips_path, "im_affine :input :output :scale 0 0 :scale 0 0 :x :y :w :h")
        line.run(:output => "#{output_path}#{quality_extension}",
                 :input => input_path,
                 :scale => transform[:scale].to_s,
                 :x => transform[:x].to_s,
                 :y => transform[:y].to_s,
                 :w => transform[:w].to_s,
                 :h => transform[:h].to_s)
      end

      FileUtils.rm(input_path)


      output_path
    end

    def handle_exif_rotation(input_path, original_format)
      return unless original_format == 'JPEG'

      # find the EXIF values
      orientation = EXIFR::JPEG.new(input_path).orientation.to_i

      if orientation == 3
        command = 'im_rot180'
      elsif orientation == 6
        command = 'im_rot90'
        return_value = :swap_dimensions
      elsif orientation == 8
        command = 'im_rot270'
        return_value = :swap_dimensions
      else
        return
      end

      intermediate_path = "#{input_path}_rotated.jpg"
      intermediate_quality_extension = ':90'

      line = Cocaine::CommandLine.new(@vips_path, ":command :input :intermediate_path")
      line.run(:input => input_path,
               :intermediate_path => "#{intermediate_path}#{intermediate_quality_extension}",
               :command => command)

      # mogrify strips the EXIF tags so that browsers that support EXIF don't rotate again after
      # we have rotated
      line = Cocaine::CommandLine.new('mogrify', "-strip :intermediate_path")
      line.run(:intermediate_path => intermediate_path)

      FileUtils.mv(intermediate_path, input_path)

      return_value
    end

  end
end

