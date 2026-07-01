require 'test/unit'
require 'tmpdir'
require 'open3'
require 'nokogiri'
require 'fileutils'

class IntegrationTest < Test::Unit::TestCase
  FIXTURES_DIR = File.join(__dir__, 'fixtures')
  GEM_ROOT = File.expand_path('..', __dir__)

  def setup
    @tmpdir = Dir.mktmpdir('simplecov-cobertura-integration')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_clean_load_require_and_assign_formatter
    # In a fresh subprocess, require simplecov-cobertura and assign the formatter.
    # This catches missing requires (e.g. simplecov, stringio).
    code = <<~RUBY
      require 'simplecov-cobertura'
      SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
    RUBY
    stdout, stderr, status = Open3.capture3('ruby', '-e', code)
    assert status.success?, "Clean-load subprocess failed.\nstdout: #{stdout}\nstderr: #{stderr}"
  end

  def test_real_coverage_run_produces_valid_cobertura_xml
    install_fixture('sample')

    # Run the sample test in a subprocess.
    stdout, stderr, status = run_fixture_test('test/test_sample.rb')
    assert status.success?, "Sample test subprocess failed.\nstdout: #{stdout}\nstderr: #{stderr}"

    # --- Assert on the generated coverage.xml ---
    coverage_xml_path = File.join(@tmpdir, 'coverage', 'coverage.xml')
    assert File.exist?(coverage_xml_path), "coverage.xml was not generated"
    xml_content = File.read(coverage_xml_path)
    assert !xml_content.empty?, "coverage.xml is empty"

    doc = Nokogiri::XML(xml_content) { |config| config.strict }
    assert doc.errors.empty?, "XML parse errors: #{doc.errors.join(', ')}"

    # Root element
    coverage = doc.at_xpath('/coverage')
    assert_not_nil coverage, "Missing /coverage root element"

    # Line coverage attributes — partial, not 100% and not 0%
    line_rate = coverage['line-rate'].to_f
    assert line_rate > 0.0, "line-rate should be > 0, got #{line_rate}"
    assert line_rate < 1.0, "line-rate should be < 1.0 (partial coverage), got #{line_rate}"

    lines_covered = coverage['lines-covered'].to_i
    lines_valid = coverage['lines-valid'].to_i
    assert lines_covered > 0, "lines-covered should be > 0"
    assert lines_valid > lines_covered, "lines-valid (#{lines_valid}) should be > lines-covered (#{lines_covered})"

    # Branch coverage attributes — partial
    branch_rate = coverage['branch-rate'].to_f
    assert branch_rate > 0.0, "branch-rate should be > 0, got #{branch_rate}"
    assert branch_rate < 1.0, "branch-rate should be < 1.0 (partial coverage), got #{branch_rate}"

    branches_covered = coverage['branches-covered'].to_i
    branches_valid = coverage['branches-valid'].to_i
    assert branches_covered > 0, "branches-covered should be > 0"
    assert branches_valid > branches_covered, "branches-valid (#{branches_valid}) should be > branches-covered (#{branches_covered})"

    # The sample library file appears as a class with the expected relative filename
    classes = doc.xpath('//class')
    filenames = classes.map { |c| c['filename'] }
    assert filenames.any? { |f| f.include?('lib/sample.rb') },
           "Expected a class with filename containing 'lib/sample.rb', got: #{filenames}"

    # Line-level <line> elements exist with hits and branch attributes
    lines = doc.xpath('//line')
    assert lines.length > 0, "Expected <line> elements in the output"
    lines.each do |line|
      assert_not_nil line['number'], "Line element missing 'number' attribute"
      assert_not_nil line['hits'], "Line element missing 'hits' attribute"
      assert_not_nil line['branch'], "Line element missing 'branch' attribute"
    end

    # At least one line should have branch='true' (from the if/else)
    branch_lines = lines.select { |l| l['branch'] == 'true' }
    assert branch_lines.length > 0, "Expected at least one line with branch='true'"

    # Validate condition-coverage on branch lines
    branch_lines.each do |bl|
      cc = bl['condition-coverage']
      assert_not_nil cc, "Branch line missing 'condition-coverage' attribute"
      assert_match(/\d+% \(\d+\/\d+\)/, cc, "condition-coverage format unexpected: #{cc}")
    end
  end

  def test_condition_coverage_values_are_accurate
    install_fixture('sample')

    stdout, stderr, status = run_fixture_test('test/test_sample.rb')
    assert status.success?, "Sample test subprocess failed.\nstdout: #{stdout}\nstderr: #{stderr}"

    coverage_xml_path = File.join(@tmpdir, 'coverage', 'coverage.xml')
    assert File.exist?(coverage_xml_path), "coverage.xml was not generated"
    doc = Nokogiri::XML(File.read(coverage_xml_path)) { |config| config.strict }

    # Find the branch line for the if statement in sample.rb's absolute method
    sample_class = doc.xpath('//class').find { |c| c['filename'].include?('sample.rb') }
    assert_not_nil sample_class, "Expected sample.rb class in output"

    branch_lines = sample_class.xpath('.//line[@branch="true"]')
    assert branch_lines.length > 0, "Expected branch lines in sample.rb"

    # Each if/else has 2 total branches. greet and absolute each have 1/2 covered,
    # unused_method has 0/2 covered. Verify exact values by line number.
    condition_coverages = branch_lines.map { |bl| [bl['number'].to_i, bl['condition-coverage']] }.to_h

    # greet: line 3 — only else branch taken => 50% (1/2)
    assert_equal '50% (1/2)', condition_coverages[3], "greet condition-coverage mismatch"
    # absolute: line 11 — only else branch taken => 50% (1/2)
    assert_equal '50% (1/2)', condition_coverages[11], "absolute condition-coverage mismatch"
    # unused_method: line 22 — neither branch taken => 0% (0/2)
    assert_equal '0% (0/2)', condition_coverages[22], "unused_method condition-coverage mismatch"
  end

  def test_merged_results_exercise_string_condition_keys
    install_fixture('sample')

    stdout, stderr, status = run_fixture_test('test/test_merged_a.rb',
                                              'COMMAND_NAME' => 'Run A')
    assert status.success?, "Run A failed.\nstdout: #{stdout}\nstderr: #{stderr}"

    # Tripwire: confirm the stored resultset actually contains stringified
    # condition keys. If a future simplecov changes its serialization, this
    # assertion fails and tells you this test no longer covers the string path.
    resultset = File.read(File.join(@tmpdir, 'coverage', '.resultset.json'))
    assert_match(/\[:if, \d+, \d+/, resultset,
                 'Expected stringified branch condition keys in .resultset.json')

    stdout, stderr, status = run_fixture_test('test/test_merged_b.rb',
                                              'COMMAND_NAME' => 'Run B')
    assert status.success?, "Run B failed.\nstdout: #{stdout}\nstderr: #{stderr}"

    doc = Nokogiri::XML(File.read(File.join(@tmpdir, 'coverage', 'coverage.xml'))) { |c| c.strict }
    sample_class = doc.xpath('//class').find { |c| c['filename'].include?('sample.rb') }
    assert_not_nil sample_class

    cc = sample_class.xpath('.//line[@branch="true"]')
                     .map { |l| [l['number'].to_i, l['condition-coverage']] }
                     .to_h

    # greet (line 3): else in Run A + then in Run B => merged 2/2.
    # Proves string keys were parsed AND hit counts summed across runs.
    assert_equal '100% (2/2)', cc[3], 'greet should be fully covered after merge'
    # absolute (line 11): only Run A touched it => still 1/2.
    assert_equal '50% (1/2)', cc[11]
    # unused_method (line 22): never called in either run => 0/2.
    assert_equal '0% (0/2)', cc[22]
  end

  private

  def install_fixture(name)
    FileUtils.cp_r(File.join(FIXTURES_DIR, name, '.'), @tmpdir)
  end

  def run_fixture_test(test_path, extra_env = {})
    Open3.capture3(
      { 'GEM_ROOT' => GEM_ROOT, 'PROJECT_ROOT' => @tmpdir }.merge(extra_env),
      'ruby', File.join(@tmpdir, test_path),
      chdir: @tmpdir
    )
  end

end
