# Simple database in C

Implementation through [Part 9 — Binary Search and Duplicate Keys](https://cstack.github.io/db_tutorial/parts/part9.html)
of the cstack database tutorial.

## Build and run

```sh
gcc -std=gnu11 -Wall -Wextra -Werror repl.c -o db
./db part9.db
```

```text
insert 3 user3 person3@example.com
insert 1 user1 person1@example.com
select
.constants
.btree
.exit
```

Use `.exit` to flush changes to disk. Each page is 4096 bytes. The database
currently supports one leaf node containing up to 13 rows; the next insert
returns `Error: Table full.` Binary search finds each insertion position, so
rows remain sorted by ID. Duplicate IDs return `Error: Duplicate key.` without
overwriting the existing row. As in the tutorial, a full node returns the
table-full error before checking for duplicates. Leaf splitting starts in Part 10.

The page format is unchanged from Part 8, but binary search requires sorted,
unique keys. Use a new filename such as `part9.db` if a Part 8 database contains
unsorted or duplicate IDs; there is no automatic conversion. The existing
`test.db` uses the older row format and is left intact.

## Tests

```sh
bundle install
bundle exec rspec
```

Tests compile the current source with warnings treated as errors and use
temporary database files, without changing `db` or `test.db` in the repository.
