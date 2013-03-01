Insano Image Resizer
====================

The Insano image resizer allows you to create resized versions of images, specifying a
desired width and height as well as a point of interest that the resizer will keep centered
in the frame when possible. The resizer is built on top of the VIPS command-line tool,
and is designed to be as fast as possible. In our tests, VIPS is faster than ImageMagick for any
image larger than ~300x300px, and is exponentially faster for very large images.

![A brief overview of the Insano processing function](insano_image_resizer/raw/master/samples/explanation.png)

Output formats: The Insano image resizer will keep PNGs as PNG, but any other format is converted to JPEG

* Insano is the fastest waterslide in the world. This isn't a waterslide, but it's similarly fast.

Usage
=====

In your Gemfile:

    gem 'insano_image_resizer'

Example:

    # Specify an existing image in any format supported by VIPS
    input_path = 'samples/test.jpg'

    # Create a new instance of the Image processor
    processor = ImageResizer::Processor.new(:vips_path => 'path_to_vips[defaults to vips]', :identify_path => 'path_to_ImageMagick_identify[defaults to identify]')

    # Process the image, creating a temporary file.
    output_path = processor.process(input_path, {w: 100, h: 200}, {x:986, y:820, region: 0.5})

    # Move the image to an output path
    FileUtils.mv(output_path, 'samples/output/test.jpg')

Input parameters:

The `process` method is the main function of the Insano gem. Using different parameters,
you can produce a wide range of resized images. Each of the parameters is explained below.

The first argument is an input file path. Because the Insano image resizer uses the VIPS
command line, it is not possible to transform an image that has been loaded into memory.

The second argument is a viewport hash containing width and height keys.
You can specify both width and height to produce an output image of a specific size, or provide
only width or height to have the resizer compute the other dimension based
on the aspect ratio of the image. Finally, you can pass an empty hash to use
the current width and height of the image. Note that the image resizer will
never distort an image: the output image will always fill the viewport you provide,
scaling up only if absolutely necessary.

The third parameter is the point of interest that you'd like to keep centered if possible.
Imagine that an 4:3 image contains a person's face on the left side. When you create a
square thumbnail of the image, the persons face is half chopped off, because the processor
trims off the left and right uniformly. Specifying a point of interest allows you to correct
for this problem.

By default, the POI is used only when cropping the image and deciding which sides
should be cropped off. However, specifying the optional :region parameter with a value
less than 1, you can make the image resizer zoom in around the POI, cropping the image
so that an area of size (region * image size) around the POI is visible.

Note that the output image may show more of the source image than you specify using the
interest region. The region is only meant to indicate what region you'd like to ensure makes
it into the output. For example, if you have a 200 x 200px image and request an output image of
100 x 100px, showing the 50px region around 150px x 150px, the output will contain more than
just that region, since filling a 100px square with a 50px region would require enlarging the
source image.

Credits
=======

This project draws heavily on the VIPS im_affinei command line function to resize images using an affine transform.

