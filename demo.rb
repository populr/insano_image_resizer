$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.dirname(__FILE__) + '/lib')
require 'image_resizer'
require 'pry'
require 'pry-nav'
require 'pry-stack_explorer'

input_path = 'samples/test.jpg'

processor = ImageResizer::Processor.new
output_path = processor.process(input_path, {w: 100, h: 200}, {x:986, y:820})
FileUtils.mv(output_path, 'samples/output/test.jpg')