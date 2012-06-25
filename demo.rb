$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.dirname(__FILE__) + '/lib')
require 'image_resizer'
require 'pry'
require 'pry-nav'
require 'pry-stack_explorer'

input_path = 'samples/test.png'

processor = ImageResizer::Processor.new
output_path = processor.process(input_path, {w: 100, h: 100}, {x:125, y:125, region:0.6})
FileUtils.mv(output_path, 'samples/output/test.png')