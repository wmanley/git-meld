#!/bin/bash -e

#
# For these tests meld is mocked out and replaced by a bash function.  Each
# test case is made up of a pair of functions test_xxx and xxx_handler.
# test_xxx typically will invoke git-meld and xxx_handler will be *invoked by*
# git-meld.  The success of the test depends on the exit code of the handler.
#
# This means that:
#  - test_xxx sets up some conditions and invokes git-meld with some arguments
#  - xxx_handler checks that git-meld would invoke meld correctly (i.e. with
#    the correct arguments and filesystem contents
#

this_script=$(readlink -f $BASH_SOURCE)
git_meld=$(dirname "$this_script")/git-meld.pl
handler=$1

function setup {
    export repo_dir=$(mktemp -d -t git-meld.XXXXXX)
    cd "$repo_dir"

    git init
    echo "Some file" > a
    git add a
    git commit -m "Added some file"
    echo "Another file" > b
    git add b
    git commit -m "Added another file"
    git checkout -b branch-1 HEAD^
    echo "b with some different content" > b
    git add b
    git commit -a -m "More changes"
    git checkout -b branch-2 HEAD^
    echo "An indexed file" > wtf
    git add wtf
    echo "And some changes to it" > wtf

    git config treediff.tool test_checker
    git config treediff.test_checker.cmd "$this_script"
}

function teardown {
    rm -Rf "$repo_dir"
}

function die {
    echo $1
    exit 1
}

function assert_file_contents_equal_to {
    tmp=$(mktemp -t expected-contents.XXXXXX)
    echo $2 > "$tmp"
    cmp "$1" "$tmp" || diff "$1" "$tmp" || die "Assertion failed: $1 contains '$2'"
}

###### test 1
function test_compare_index_to_working_dir {
    "$git_meld"
}

function compare_index_to_working_dir_handler {
    assert_file_contents_equal_to $tree_a/wtf "An indexed file"
    assert_file_contents_equal_to $tree_b/wtf "And some changes to it"
    [ $(readlink -f $tree_b/wtf) == $(readlink -f $repo_dir/wtf) ] \
        || die "When comparing against the working tree symbolic links rather than copies should be created"
}

###### test 2
function test_compare_HEAD_to_working_dir {
    "$git_meld" HEAD
}

function compare_HEAD_to_working_dir_handler {
    [ ! -e $tree_a/wtf ] || die "$tree_a/wtf is not in HEAD, so shouldn't be here"
    assert_file_contents_equal_to $tree_b/wtf "And some changes to it"
    [ $(readlink -f $tree_b/wtf) == $(readlink -f $repo_dir/wtf) ] \
        || die "When comparing against the working tree symbolic links rather than copies should be created"
}

###### test 3
function test_compare_HEAD_to_index {
    "$git_meld" --cached
}

function compare_HEAD_to_index_handler {
    [ ! -e $tree_a/wtf ] || die "$tree_a/wtf is not in HEAD, so shouldn't be here"
    assert_file_contents_equal_to $tree_b/wtf "An indexed file"
}

###### test 4
function test_compare_branch1_to_branch2 {
    "$git_meld" branch-1 branch-2
}

function compare_branch1_to_branch2_handler {
    assert_file_contents_equal_to $tree_a/b "b with some different content"
    [ -z "$(ls -A $tree_b)" ] || die "$tree_b should be empty"
}

##### test 5
# Regression test for bug reported by Adam Dingle and fixed in commit
# 181b1f2adcbd53eea488ef027baf9942bfe3620f
function test_that_git_meld_works_with_branches_with_slashes_in_their_names {
    git branch branch/with/slashes branch-1
    "$git_meld" branch/with/slashes branch-2
}

function that_git_meld_works_with_branches_with_slashes_in_their_names_handler {
    assert_file_contents_equal_to $tree_a/b "b with some different content"
    [ -z "$(ls -A $tree_b)" ] || die "$tree_b should be empty"
}

##### test 6
function test_that_git_meld_works_when_not_invoked_from_root_of_repo {
    mkdir moo
    cd moo
    "$git_meld" branch-1 branch-2
}

function that_git_meld_works_when_not_invoked_from_root_of_repo_handler {
    assert_file_contents_equal_to "$tree_a/b" "b with some different content"
    [ -z "$(ls -A $tree_b)" ] || die "$tree_b should be empty"
}

# If the variable $test_handler is not set this script should run through all
# the tests.  The tests involve instructing git-meld to invoke this script
# rather than meld itself with the $test_handler variable set so we can check if
# the appropriate environment would have been set up for meld.
if [ -z "$test_handler" ]; then
    ## foreach test
    declare -F | cut -d' ' -f 3 | grep test_ | sed s/test_// |
    {
        while read line
        do
            [ "$1" == '-v' ] && echo "Running test test_$line..."
            setup &> /dev/null
            export test_handler=${line}_handler
            test_$line && echo "SUCCESS test_$line" || echo "FAILURE test_$line"
            teardown &> /dev/null
        done
    }
else
    tree_a=$1
    tree_b=$2
    "$test_handler"
fi
