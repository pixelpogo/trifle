require "spec_helper"

describe Trifle::Loader do

  before do
    @loader = Trifle::Loader.new(Redis.new)
    @valid_data = [
      ["223.255.254.0","223.255.254.255","3758095872","3758096127","SG","Singapore"],
      ["223.255.255.0","223.255.255.255","3758096128","3758096383","AU","Australia"]
    ]
    @csv = <<-EOD
"223.255.254.0","223.255.254.255","3758095872","3758096127","SG","Singapore"
"223.255.255.0","223.255.255.255","3758096128","3758096383","AU","Australia"
    EOD
  end

  it "should extend InitializeWithRedis" do
    Trifle::Loader.included_modules.should include(Trifle::InitializeWithRedis)
  end

  describe "#handle" do

    context "when given the :filename option" do
      it "should pass it on to load_files" do
        filename = 'data.csv'
        @loader.should_receive(:load_files).with([filename])
        @loader.handle(filename: filename)
      end
    end

    context "when given the :filenames option" do
      it "should pass it on to load_files" do
        filenames = ['data1.csv', 'data2.csv']
        @loader.should_receive(:load_files).with(filenames)
        @loader.handle(filenames: filenames)
      end
    end

    context "when given the :data option" do
      it "should pass it on to load_data" do
        data = [:foo, :bar]
        @loader.should_receive(:load_data).with(data)
        @loader.handle(data: data)
      end
    end

    context "when given anything else" do
      it "should raise an error" do
        -> { @loader.handle(foo: :bar) }.should raise_error(ArgumentError)
        -> { @loader.handle }.should raise_error(ArgumentError)
      end
    end
  end

  describe "#load_files" do
    context "when given a valid list of files" do
      before do
        @filenames = ['foo.csv', 'bar.csv']
        file = mock File
        file.should_receive(:read).twice.and_return(@csv)
        File.should_receive(:open).twice.and_return(file)
      end

      it "should read the files" do
        @loader.load_files @filenames
        @loader.redis.llen(Trifle::KEY).should be == 4
      end
    end

    context "when given anything but an array of strings" do
      it "should raise an error" do
        -> { @loader.load_files "" }.should raise_error(ArgumentError)
        -> { @loader.load_files [:foo] }.should raise_error(ArgumentError)
      end
    end

    context "when given a filename for a file that's missing" do
      it "should raise an error" do
        -> { @loader.load_files ["foobar.csv"] }.should raise_error(/No such file or directory - foobar.csv/)
      end
    end
  end

  describe "#load_data" do

    context "when given valid data" do
      it "should clear out existing data" do
        @loader.should_receive(:clear)
        @loader.load_data @valid_data
      end

      it "should validate the data" do
        @loader.should_receive(:valid?).and_return(true)
        @loader.load_data @valid_data
      end

      it "should load it in redis" do
        @loader.load_data @valid_data
        @loader.redis.llen(Trifle::KEY).should be == 2
      end
    end

    context "when given invalid data" do
      it "should raise an error" do
        @loader.should_receive(:valid?).and_return(false)
        -> { @loader.load_data @valid_data }.should raise_error(ArgumentError)
      end
    end

    context "when given anything but an array" do
      it "should raise an error" do
        -> { @loader.load_data :rubbish }.should raise_error(ArgumentError)
      end
    end
  end

  describe "#parse" do
    it "should parse valid csv data" do
      @loader.parse(@csv).should be == @valid_data
    end

    it "should raise an error for invalid csv data" do
      -> { @loader.parse('"foo",","#') }.should raise_error(CSV::MalformedCSVError)
    end

    it "should handle ipv6 data" do
      @ipv6csv = <<-CSV
"2c0f:ffe8::", "2c0f:ffe8:ffff:ffff:ffff:ffff:ffff:ffff", "58569106662796955307479896348547874816", "58569106742025117821744233942091825151", "NG", "Nigeria"
"2c0f:fff0::", "2c0f:fff0:ffff:ffff:ffff:ffff:ffff:ffff", "58569107296622255421594597096899477504", "58569107375850417935858934690443427839", "NG", "Nigeria"
      CSV
      -> { @loader.parse(@ipv6csv) }.should_not raise_error
    end
  end

  describe "#sort" do
    it "should sort the data" do
      @loader.sort(@valid_data.reverse).should be == @valid_data
    end
  end


  describe "#valid?" do
    it "should mark valid data as such" do
      @loader.valid?(@valid_data).should be_true
    end

    it "should mark invalid data as such" do
      invalid_data =  []
      @loader.valid?(invalid_data).should be_false
      invalid_data = [
        ["223.255.254.0","223.255.254.255","not_a_number","3758096127","SG","Singapore"]
      ]
      @loader.valid?(invalid_data).should be_false
      invalid_data = [
        ["223.255.254.0","223.255.254.255","3758095872","not_a_number","SG","Singapore"]
      ]
      @loader.valid?(invalid_data).should be_false
    end
  end

  describe "#clear" do
    it "should clear existing data" do
      @loader.load_data @valid_data
      @loader.clear
      @loader.redis.llen(Trifle::KEY).should be == 0
    end
  end

end