#!/usr/bin/perl

### Copyright (C) 2010 Will Manley <will@williammanley.net>

### This program is free software; you can redistribute it and/or modify
### it under the terms of the GNU General Public License as published by
### the Free Software Foundation; either version 2 of the License, or
### (at your option) any later version.

### This program is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### GNU General Public License for more details.

### You should have received a copy of the GNU General Public License
### along with this program; if not, write to the Free Software
### Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;

sub safe_cmd {
	my $cmd = shift;
	my $output = `$cmd`;
	if ($? != 0) {
		die("$cmd failed with exit code $?");
	}
	return $output;
}

sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# The command line possibilities are:
#     Compare HEAD to working directory:
#         git meld [--options...] [--] [<paths>...]
#
#     Show the differences between source and the working directory
#         git meld [--options...] <source> [--] [<paths>...]
#
#     Show the differences between source and dest:
#         git meld [--options...] <source> <dest> [--] [<paths>...]
#
#     Same as above:
#         git meld [--options...] <source>..<dest> [--] [<paths>...]
#
#     Show all the changes in source that have occured since it was branched
#     from dest:
#         git meld [--options...] <commit1>...<commit2> [--] [<paths>...]
#
# This function parses the command line and extracts source and dest and returns
# them as two elements in a list.
sub parse_cmd(@)
{
    my @args = @_;
    my $diff_opts = "";
    my $source_tree = "";
    my $dest_tree = "";

    # Get options to be sent to diff.  These all start with --
    while (my $arg = shift(@args)) {
	    if ($arg =~ m/^-/ && $arg != "--") {
		    $diff_opts += " \"$arg\"";
	    }
	    else {
		    unshift(@args, $arg);
		    last;
	    }
	    if ($arg == "--cached") {
		    die ("--cached option not supported");
	    }
    }

    my $source_tree = "";
    my $dest_tree = "";

    # Get tree-ishes to compare
    if (scalar @args != 0 && $args[0] ne "--") {
        my $commit1 = shift(@args);

        if ($commit1 =~ m/^(.*)\.\.\.(.*)$/) {
	        $source_tree = trim(safe_cmd("git merge-base $1 $2"));
	        $dest_tree = $2;
	        shift(@args);
        }
        elsif ($commit1 =~ m/^(.*)\.\.(.*)$/) {
	        $source_tree = $1;
	        $dest_tree = $2;
        }
        else {
	        $source_tree = $commit1;
	        if (scalar @args == 0) {
	        }
	        else {
		        my $commit2 = shift(@args);
		        if ($commit2 ne "--") {
			        $dest_tree = $commit2;
		        }
	        }
        }
    }
    return ($source_tree, $dest_tree);
}

my $all_args = "\"" . join("\" \"", @ARGV) . "\"";
(my $source_tree, my $dest_tree) = parse_cmd(@ARGV);

if ($source_tree eq "" && $dest_tree eq "") {
    safe_cmd("meld ./");
    exit(0);
}

# At this point we have parsed two commits and want to diff them
my $git_dir = trim(safe_cmd("git rev-parse --show-cdup"));
if ($git_dir eq "") {
	$git_dir = ".";
}
my $changed_files=safe_cmd("git diff --name-only $all_args");
$changed_files =~ s/\n/ /g;

my $tmp_dir=trim(safe_cmd("mktemp -d"));
my $source_dir = "$tmp_dir/$source_tree";
my $dest_dir;
if ($dest_tree eq "") {
	$dest_dir = "$tmp_dir/working_dir";
}
else {
	$dest_dir = "$tmp_dir/$dest_tree";
}

system("mkdir $source_dir");
system("mkdir $dest_dir");
safe_cmd("git archive $source_tree $changed_files | tar -x -C $source_dir");
if ($dest_tree eq "") {
	die("Diff to working directory not yet implemented!");
	safe_cmd("cp -l -R $changed_files $dest_dir");
}
else {
	safe_cmd("git archive $dest_tree $changed_files | tar -x -C $dest_dir");
}

system("chmod -R a-w $tmp_dir/*");

safe_cmd("meld $source_dir $dest_dir");

system("chmod -R u+w $tmp_dir/*");
system("rm -Rf $tmp_dir");
