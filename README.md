Insano Image Resizer
====================

The Insano image resizer allows you to create resized versions of images, specifying a 
desired width and height as well as a point of interest that the resizer will keep centered
in the frame when possible. The resizer is built on top of the VIPS command-line tool, 
and is designed to be as fast as possible. In our tests, VIPS is faster than ImageMagick for any 
image larger than ~300x300px, and is exponentially faster for very large images. 

Output formats: The Insano image resizer will produce either a PNG or JPG image, depending
on whether the source image includes transparency.

* Insano is the fastest waterslide in the world. This isn't a waterslide, but it's similarly fast.

Usage
=====

In your Gemfile:

    gem 'insano_resizer'

Example:

    # Specify an existing image in any format supported by VIPS
    input_path = 'samples/test.jpg'

    # Create a new instance of the Image processor
    processor = ImageResizer::Processor.new
    
    # Process the image, creating a temporary file. The path to the temporary file
    # is returned. The first argument is the input file path, the second argument
    # is the width and height you want. You can specify only width or height, and 
    # the resizer will compute the other dimension to keep the image at its current
    # aspect ratio. The third parameter is the point of interest that you'd like
    # to keep centered if possible. By default, the POI is used only when cropping
    # the image and deciding which sides should be cropped off. However, by 
    # specifying a region less than 1, you can make the image resizer zoom in around
    # the POI, cropping the image so that an area of size (region * image size) 
    # around the POI is visible. 
    output_path = processor.process(input_path, {w: 100, h: 200}, {x:986, y:820, region: 0.5})
    
    # Move the image to an output path
    FileUtils.mv(output_path, 'samples/output/test.jpg')


Credits
=======

This project is loosely based off of the ImageResizer gem previously authored by Daniel Nelson of Populr.me.
It draws heavily on the VIPS im_affinei command line function to resize images using an affine transform.

