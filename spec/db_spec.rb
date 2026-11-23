require 'open3'
require 'tmpdir'

describe 'database' do
  before(:all) do
    @build_dir = Dir.mktmpdir('db-build-')
    @binary = File.join(@build_dir, 'db')
    source = File.expand_path('../repl.c', __dir__)
    output, status = Open3.capture2e(ENV.fetch('CC', 'gcc'), '-std=gnu11',
                                   '-Wall', '-Wextra', '-Werror', source, '-o', @binary)
    raise "Compilation failed:\n#{output}" unless status.success?
  end

  after(:all) { FileUtils.remove_entry(@build_dir) }

  around do |example|
    Dir.mktmpdir('db-spec-') do |directory|
      @database = File.join(directory, 'test.db')
      example.run
    end
  end

  def run_script(commands)
    output, status = Open3.capture2e(@binary, @database,
                                   stdin_data: commands.join("\n") + "\n")
    expect(status.success?).to be(true), output
    output.split("\n")
  end

  it 'inserts and retrieves a row' do
    expect(run_script(['insert 1 user1 person1@example.com', 'select', '.exit'])).to eq([
      'db > Executed.',
      'db > (1, user1, person1@example.com)',
      'Executed.',
      'db > ',
    ])
  end

  it 'rejects the fourteenth row without losing the first thirteen' do
    script = (1..14).map { |i| "insert #{i} user#{i} person#{i}@example.com" }
    result = run_script(script + ['.exit'])
    expect(result).to eq(['db > Executed.'] * 13 + ['db > Error: Table full.', 'db > '])

    result = run_script(['select', '.exit'])
    expect(result[0]).to eq('db > (1, user1, person1@example.com)')
    expect(result[12]).to eq('(13, user13, person13@example.com)')
    expect(result.length).to eq(15)
  end

  it 'accepts strings at the maximum length' do
    username = 'a' * 32
    email = 'b' * 255
    run_script(["insert 1 #{username} #{email}", '.exit'])
    expect(run_script(['select', '.exit'])).to eq([
      "db > (1, #{username}, #{email})", 'Executed.', 'db > ',
    ])
  end

  it 'rejects strings longer than either column allows' do
    expect(run_script([
      "insert 1 #{'a' * 33} a@example.com",
      "insert 2 user2 #{'a' * 256}",
      'select', '.exit',
    ])).to eq([
      'db > String is too long.', 'db > String is too long.',
      'db > Executed.', 'db > ',
    ])
  end

  it 'rejects a negative id' do
    expect(run_script(['insert -1 user1 person1@example.com', 'select', '.exit'])).to eq([
      'db > ID must be positive.', 'db > Executed.', 'db > ',
    ])
  end

  it 'reports invalid statements and meta commands' do
    expect(run_script(['insert 1', 'invalid', '.invalid', '.exit'])).to eq([
      'db > Syntax error. Could not parse statement.',
      "db > Unrecognized keyword at start of 'invalid'.",
      "db > Unrecognized command '.invalid'", 'db > ',
    ])
  end

  it 'persists a full page and allows more inserts after reopening' do
    run_script(['insert 3 user3 person3@example.com', '.exit'])
    expect(File.size(@database)).to eq(4096)
    run_script(['insert 1 user1 person1@example.com', '.exit'])
    expect(run_script(['select', '.exit'])).to eq([
      'db > (1, user1, person1@example.com)',
      '(3, user3, person3@example.com)', 'Executed.', 'db > ',
    ])
    expect(File.size(@database)).to eq(4096)
  end

  it 'initializes and persists an empty leaf' do
    expected = ['db > Executed.', 'db > Tree:', 'leaf (size 0)', 'db > ']
    expect(run_script(['select', '.btree', '.exit'])).to eq(expected)
    expect(File.size(@database)).to eq(4096)
    expect(run_script(['select', '.btree', '.exit'])).to eq(expected)
  end

  it 'prints the Part 8 storage constants' do
    expect(run_script(['.constants', '.exit'])).to eq([
      'db > Constants:', 'ROW_SIZE: 293', 'COMMON_NODE_HEADER_SIZE: 6',
      'LEAF_NODE_HEADER_SIZE: 10', 'LEAF_NODE_CELL_SIZE: 297',
      'LEAF_NODE_SPACE_FOR_CELLS: 4086', 'LEAF_NODE_MAX_CELLS: 13', 'db > ',
    ])
  end

  it 'prints leaf keys in sorted order, including after reopening' do
    script = [3, 1, 2].map { |i| "insert #{i} user#{i} person#{i}@example.com" }
    expected_tree = ['db > Tree:', 'leaf (size 3)',
                     '  - 0 : 1', '  - 1 : 2', '  - 2 : 3', 'db > ']
    expect(run_script(script + ['.btree', '.exit'])).to eq(
      ['db > Executed.'] * 3 + expected_tree
    )
    expect(run_script(['.btree', '.exit'])).to eq(expected_tree)
  end

  it 'inserts at the beginning, middle and end while preserving complete rows' do
    script = [7, 3, 11, 0, 13, 5, 9, 1, 12, 4, 8, 2, 6].map do |i|
      "insert #{i} user#{i} person#{i}@example.com"
    end
    run_script(script + ['.exit'])
    expected_rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13].map do |i|
      "(#{i}, user#{i}, person#{i}@example.com)"
    end
    expected_rows[0] = "db > #{expected_rows[0]}"
    expect(run_script(['select', '.exit'])).to eq(expected_rows + ['Executed.', 'db > '])
  end

  it 'rejects duplicate ids at each position without overwriting existing rows' do
    script = [2, 1, 3].map { |i| "insert #{i} user#{i} person#{i}@example.com" }
    duplicates = [1, 2, 3].map { |i| "insert #{i} changed changed@example.com" }
    expect(run_script(script + duplicates + ['.exit'])).to eq(
      ['db > Executed.'] * 3 + ['db > Error: Duplicate key.'] * 3 + ['db > ']
    )
    expect(run_script(['insert 2 changed changed@example.com', 'select', '.btree', '.exit'])).to eq([
      'db > Error: Duplicate key.',
      'db > (1, user1, person1@example.com)',
      '(2, user2, person2@example.com)', '(3, user3, person3@example.com)',
      'Executed.', 'db > Tree:', 'leaf (size 3)',
      '  - 0 : 1', '  - 1 : 2', '  - 2 : 3', 'db > ',
    ])
  end

  it 'rejects an old or incomplete database page without changing it' do
    contents = 'x' * 293
    File.binwrite(@database, contents)
    output, status = Open3.capture2e(@binary, @database, stdin_data: ".exit\n")
    expect(status.success?).to be(false)
    expect(output).to eq("Db file is not a whole number of pages. Corrupt file.\n")
    expect(File.binread(@database)).to eq(contents)
  end

  it 'requires a database filename' do
    output, status = Open3.capture2e(@binary)
    expect(status.success?).to be(false)
    expect(output).to eq("Must supply a database filename.\n")
  end
end
