require 'spec_helper'

describe InsanoImageResizer::Shell do

  include InsanoImageResizer::Shell

  it "should raise an error if the identify command isn't found" do
    suppressing_stderr do
      lambda{
        run "non-existent-command"
      }.should raise_error(InsanoImageResizer::Shell::CommandFailed)
    end
  end

  describe "escaping args" do
    {
      %q(hello) => %q('hello'),
      %q("hello") => %q('hello'),
      %q('hello') => %q('hello'),
      %q(he\'llo) => %q('he'\''llo'),
      %q('he'\''llo') => %q('he'\''llo'),
      %q("he'llo") => %q('he'\''llo'),
      %q(hel$(lo)) => %q('hel$(lo)'),
      %q(hel\$(lo)) => %q('hel$(lo)'),
      %q('hel\$(lo)') => %q('hel\$(lo)')
    }.each do |args, escaped_args|
      it "should escape #{args.inspect} -> #{escaped_args.inspect}" do
        pending "not applicable to windows" if running_on_windows?
        escape_args(args).should == escaped_args
      end
    end
  end

end
