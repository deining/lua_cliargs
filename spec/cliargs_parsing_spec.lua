local cli, defaults, result

-- some helper stuff for debugging
local quoted = function(s)
  return "'" .. tostring(s) .. "'"
end
local dump = function(t)
  print(" ============= Dump " .. tostring(t) .. " =============")
  if type(t) ~= "table" then
    print(quoted(tostring(t)))
  else
    for k,v in pairs(t) do
      print(quoted(k),quoted(v))
    end
  end
  print(" ============= Dump " .. tostring(t) .. " =============")
end

-- fixture
local function populate_required()
  cli:add_argument("INPUT", "path to the input file")

  return { ["INPUT"] = nil }
end
local function populate_optarg(cnt)
  cnt = cnt or 1
  cli:optarg("OUTPUT", "path to the output file", "./out", cnt)
  if cnt == 1 then
    return { OUTPUT = "./out" }
  else
    return { OUTPUT = {"./out"}}
  end
end
local function populate_optionals()
  cli:add_option("-c, --compress=FILTER", "the filter to use for compressing output: gzip, lzma, bzip2, or none", "gzip")
  cli:add_option("-o FILE", "path to output file", "/dev/stdout")

  return { c = "gzip", compress = "gzip", o = "/dev/stdout" }
end
local function populate_flags()
  cli:add_flag("-v, --version", "prints the program's version and exits")
  cli:add_flag("-d", "script will run in DEBUG mode")
  cli:add_flag("--verbose", "the script output will be very verbose")

  return { d = nil, v = nil, version = nil, verbose = nil }
end

-- start tests
describe("Testing cliargs library parsing commandlines", function()
  setup(function()
    _G._TEST = true
  end)

  teardown(function()
    _G._TEST = nil
  end)

  before_each(function()
    _G.arg = nil
    package.loaded.cliargs = nil  -- Busted uses it, but must force to reload
    cli = require("cliargs")
  end)

  it("tests no arguments set, nor provided", function()
    local args = {}
    result = cli:parse(args)
    assert.are.same(result, {})
  end)

  it("tests uses global arg if arguments set not passed in", function()
    _G.arg = { "--version" }
    defaults = populate_flags(cli)
    defaults.v = true
    defaults.version = true
    result = cli:parse(true --[[no print]])
    assert.are.same(result, defaults)
  end)

  it("tests only optionals, nothing provided", function()
    local args = {}
    defaults = populate_optionals(cli)
    result = cli:parse(args)
    assert.are.same(result, defaults)
  end)

  it("tests only required, all provided", function()
    local args = { "some_file" }
    populate_required(cli)
    result = cli:parse(args)
    assert.are.same(result, { ["INPUT"] = "some_file" })
  end)

  it("tests only optionals, all provided", function()
    local args = { "-o", "/dev/cdrom", "--compress=lzma" }
    populate_optionals(cli)
    result = cli:parse(args)
    assert.are.same(result, { o = "/dev/cdrom", c = "lzma", compress = "lzma" })
  end)

  it("tests optionals + required, all provided", function()
    local args = { "-o", "/dev/cdrom", "-c", "lzma", "some_file" }
    populate_required(cli)
    populate_optionals(cli)
    result = cli:parse(args)
    assert.are.same(result, {
      o = "/dev/cdrom",
      c = "lzma", compress = "lzma",
      ["INPUT"] = "some_file"
    })
  end)

  it("tests optional using -short-key notation", function()
    defaults = populate_optionals(cli)
    defaults.c = "lzma"
    defaults.compress = "lzma"

    result = cli:parse({ "-c", "lzma" })
    assert.are.same(result, defaults)
  end)

  it("tests option using -short-key value notation", function()
    _G.arg = { "-out", "outfile" }
    cli:add_opt("-out VALUE", "output file")
    defaults = { out = "outfile" }
    result = cli:parse()
    assert.are.same(result, defaults)
  end)

  it("tests optional using --expanded-key notation, --x=VALUE", function()
    defaults = populate_optionals(cli)
    defaults.c = "lzma"
    defaults.compress = "lzma"

    result = cli:parse({ "--compress=lzma" })

    assert.are.same(result, defaults)
  end)

  it("tests optional using alternate --expanded-key notation, --x VALUE", function()
    defaults = populate_optionals(cli)
    defaults.c = "lzma"
    defaults.compress = "lzma"

    result = cli:parse({ "--compress", "lzma" })

    assert.are.same(result, defaults)
  end)

  describe("multiple values for a single key", function()
    it("should work for keys that explicitly permit it", function()
      cli:add_option("-k, --key=VALUE", "key that can be specified multiple times", {})

      defaults = { key = {"value1", "value2", "value3"} }
      defaults.k = defaults.key

      result = cli:parse({ "--key", "value1", "-k", "value2", "--key=value3" })

      assert.are.same(result, defaults)
    end)

    it("should bail if the default value is not an empty table", function()
      assert.is.error(function()
        cli:add_option("-k", "a key that can be specified multiple times", { "foo" })
      end, "Default argument: expected a")
    end)

    it("should print [] as the default value in the --help listing", function()
      cli:add_option("-k, --key=VALUE", "key that can be specified multiple times", {})

      local help_msg = cli:print_help(true)

      assert.is_true(
        nil ~= help_msg:match("key that can be specified multiple times %(default: %[%]%)")
      )
    end)
  end)

  describe("flag options", function()
    it("should turn them on using the -short-key notation", function()
      defaults = populate_flags(cli)
      defaults.v = true
      defaults.version = true
      result = cli:parse({ "-v" })
      assert.are.same(result, defaults)
    end)

    it("should turn them on using the --expanded-key notation", function()
      defaults = populate_flags(cli)
      defaults.v = true
      defaults.version = true
      result = cli:parse({ "--version" })
      assert.are.same(result, defaults)
    end)

    describe("given a -short-key only flag option", function()
      it("works", function()
        cli:add_flag("-d", "script will run in DEBUG mode")
        result = cli:parse({ "-d" })
        assert.are.same(result, { d = true })
      end)
    end)

    describe("given an --expanded-key only flag option", function()
      it("works", function()
        defaults = populate_flags(cli)
        defaults.verbose = true
        result = cli:parse({ "--verbose" })
        assert.are.same(result, defaults)
      end)
    end)

    describe("given a value for a flag", function()
      it("bails", function()
        local err

        defaults = populate_flags(cli)
        defaults.verbose = true
        result, err = cli:parse({ "--verbose=something" }, true --[[no print]])

        assert(result == nil, "Adding a value to a flag must error out")
        assert(type(err) == "string", "Expected an error string")
      end)
    end)
  end)

  it("tests optionals + required, no optionals and to little required provided, ", function()
    populate_required(cli)
    populate_optionals(cli)
    result = cli:parse({}, true --[[no print]])
    assert.is.falsy(result)
  end)

  it("tests optionals + required, no optionals and too many required provided, ", function()
    populate_required(cli)
    populate_optionals(cli)
    result = cli:parse({ "some_file", "some_other_file" }, true --[[no print]])
    assert.is.falsy(result)
  end)

  it("tests optionals + required + optarg, '--' as end of optionals", function()
    populate_required(cli)
    populate_optarg(1)
    local expected = populate_flags(cli)
    expected.INPUT = "--input"
    expected.OUTPUT = "-d"
    expected.verbose = true
    local result = cli:parse({ "--verbose", "--", "--input", "-d" })
    assert.is.same(expected, result)
  end)

  it("tests bad short-key notation, -x=VALUE", function()
    populate_optionals(cli)
    result = cli:parse({ "-o=some_file" }, true --[[no print]])
    assert.is.falsy(result)
  end)

  it("tests unknown option", function()
    populate_optionals(cli)
    result = cli:parse({ "--foo=bar" }, true --[[no print]])
    assert.is.falsy(result)
  end)

  it("tests unknown flag", function()
    populate_optionals(cli)
    result = cli:parse({ "--foo" }, true --[[no print]])
    assert.is.falsy(result)
  end)

  it("tests optarg only, defaults, multiple allowed", function()
    defaults = populate_optarg(3)
    result,err = cli:parse(true --[[no print]])
    assert.is.same(defaults, result)
  end)

  it("tests optarg only, defaults, 1 allowed", function()
    defaults = populate_optarg(1)
    result = cli:parse(true --[[no print]])
    assert.is.same(defaults, result)
  end)

  it("tests optarg only, values, multiple allowed", function()
    defaults = populate_optarg(3)
    result = cli:parse({"/output1/", "/output2/"}, true --[[no print]])
    assert.is.same(result, { OUTPUT = {"/output1/", "/output2/"}})
  end)

  it("tests optarg only, values, 1 allowed", function()
    defaults = populate_optarg(1)
    result = cli:parse({"/output/"}, true --[[no print]])
    assert.is.same(result, { OUTPUT = "/output/" })
  end)

  it("tests optarg only, too many values", function()
    defaults = populate_optarg(1)
    result = cli:parse({"/output1/", "/output2/"}, true --[[no print]])
    assert.is.same(result, nil)
  end)

  it("tests optarg only, too many values", function()
    populate_required()
    populate_optarg(1)
    result = cli:parse({"/input/", "/output/"}, true --[[no print]])
    assert.is.same(result, { INPUT = "/input/", OUTPUT = "/output/" })
  end)

  it("tests clearing the default of an optional", function()
    local err
    populate_optionals(cli)
    result, err = cli:parse({ "--compress=" }, true --[[no print]])
    assert.are.equal(nil,err)
    -- are_not.equal is not working when comparing against a nil as
    -- of luassert-1.2-1, using is.truthy instead for now
    -- assert.are_not.equal(nil,result)
    assert.is.truthy(result)
    assert.are.equal("", result.compress)
  end)

  describe("Tests parsing with callback", function()
    local cb = {}

    local function callback(key, value, altkey, opt)
      cb.key, cb.value, cb.altkey = key, value, altkey
      return true
    end
    local function callback_fail(key, value, altkey, opt)
      return nil, "bad argument to " .. opt
    end

    before_each(function()
      cb = {}
    end)

    it("tests short-key option", function()
      cli:add_option("-k, --long-key=VALUE", "key descriptioin", "", callback)
      local expected = { k = "myvalue", ["long-key"] = "myvalue" }
      local result = cli:parse({ "-k", "myvalue" })
      assert.are.same(expected, result)
      assert.are.equal(cb.key, "k")
      assert.are.equal(cb.value, "myvalue")
      assert.are.equal(cb.altkey, "long-key")
    end)

    it("tests expanded-key option", function()
      cli:add_option("-k, --long-key=VALUE", "key descriptioin", "", callback)
      local expected = { k = "val", ["long-key"] = "val" }
      local result = cli:parse({ "--long-key", "val" })
      assert.are.same(expected, result)
      assert.are.equal(cb.key, "long-key")
      assert.are.equal(cb.value, "val")
      assert.are.equal(cb.altkey, "k")
    end)

    it("tests expanded-key flag with not short-key", function()
      cli:add_flag("--version", "prints the version and exits", callback)
      local expected = { version = true }
      local result = cli:parse({ "--version" })
      assert.are.same(expected, result)
      assert.are.equal(cb.key, "version")
      assert.are.equal(cb.value, true)
      assert.are.equal(cb.altkey, nil)
    end)

    it("tests callback returning error", function()
      cli:set_name('myapp')
      cli:add_option("-k, --long-key=VALUE", "key descriptioin", "", callback_fail)
      local result, err = cli:parse({ "--long-key", "val" }, true --[[no print]])
      assert(result == nil, "Failure in callback returns nil")
      assert(type(err) == "string", "Expected an error string")
      assert.are.equal(err, "myapp: error: bad argument to --long-key; re-run with --help for usage.")
    end)
  end)
end)
