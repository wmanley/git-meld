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
use Cwd;

sub safe_cmd {
	my $cmd = shift;
	my $output = `$cmd`;
	if ($? != 0) {
		die("$cmd failed with exit code $?");
	}
	return $output;
}

sub safe_system {
	system(@_) == 0 || die ("system(" . @_ . ") failed!");
	return 0;
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

sub nul_seperated_string_to_list($) {
    my $string = shift;
    my @list = split(/\0/, $string);
    return \@list;
}

sub shell_escape($) {
    $_ = shift;
    s/\\/\\\\/g;
    s/\$/\\\$/g;
    s/\`/\\\`/g;
    return "\"$_\"";
}

sub copy_files_named_tree($$$) {
    (my $tree, my $file_list, my $out_dir) = @_;
    if (scalar @$file_list == 0) {
        return;
    }
    my $escaped_file_list = join(" ", map{shell_escape($_)} @$file_list);
    safe_cmd("git archive $tree $escaped_file_list | tar -x -C \"$out_dir\"");
}

sub copy_files_working_dir($$) {
    (my $file_list, my $out_dir) = @_;
    # Because we're diffing against the working directory we wish to create a
    # tree of links in the dest folder mirroring that in the repo.
    # TODO: Fix this so we don't have to loop over each filename somehow
    foreach my $filename (@$file_list) {
        safe_system("ln", "-s", cwd() . "/$filename", "$out_dir/$filename");
    }
}

sub copy_files_staging_area($$) {
    (my $filelist, my $outdir) = @_;
    die("Comparison with staging area not implemented");
}

my $all_args = join(" ", map{ shell_escape($_) } @ARGV);
(my $source_tree, my $dest_tree) = parse_cmd(@ARGV);

# At this point we have parsed two commits and want to diff them
my $git_dir = trim(safe_cmd("git rev-parse --show-cdup"));
if ($git_dir eq "") {
	$git_dir = ".";
}

my $tmp_dir=trim(safe_cmd("mktemp -d"));
my $source_dir  = "$tmp_dir/" . (($source_tree eq "") ? "staging_area" : $source_tree);
my $dest_dir = "$tmp_dir/" . (($dest_tree eq "") ? "working_dir" : $dest_tree);

safe_system("mkdir $source_dir");
safe_system("mkdir $dest_dir");

my $src_changed_files = nul_seperated_string_to_list(safe_cmd("git diff -z --diff-filter=DMTUXB --name-only $all_args"));
my $dest_changed_files = nul_seperated_string_to_list(safe_cmd("git diff -z --diff-filter=ACMTUXB --name-only $all_args"));

if ($source_tree eq "") {
    copy_files_staging_area($src_changed_files, $source_dir);
}
else {
    copy_files_named_tree($source_tree, $src_changed_files, $source_dir);
}

if ($dest_tree eq "") {
    copy_files_working_dir($dest_changed_files, $dest_dir);
}
else {
    copy_files_named_tree($dest_tree, $dest_changed_files, $dest_dir);
}

safe_system("chmod -R a-w $tmp_dir/*");

safe_cmd("meld $source_dir $dest_dir");

safe_system("chmod -R u+w $tmp_dir/*");
safe_system("rm -Rf $tmp_dir");
