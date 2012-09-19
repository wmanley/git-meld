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
use File::Basename;
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

# Gets the value of the given config name from git if it exists, otherwise
# returns the default value given as the second argument
sub get_config_or_default($$) {
    (my $key, my $default) = @_;
    my $value = trim(`git config --get $key`);
    return ($value eq "") ? $default : $value;
}

# The command line possibilities are:
#     Compare staging area to working directory:
#         git meld [--options...] [--] [<paths>...]
#
#     Compare source to staging area (source defaults to HEAD):
#         git meld [--options...] --cached <source> [--] [<paths>...]
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
#         git meld [--options...] <commit1>...[<commit2>] [--] [<paths>...]
#
# This function parses the command line and extracts source and dest and returns
# them as two elements in a list.
sub parse_cmd(@)
{
    my @args = @_;
    my $diff_opts = "";
    my %opts;

    # Get options to be sent to diff.  These all start with --
    while (my $arg = shift(@args)) {
	    if ($arg =~ m/^-/ && $arg ne "--") {
            $arg =~ m/^-+([^=]+)(=(.*))?$/;
	        $opts{$1} = $3;
		    $diff_opts += " \"$arg\"";
	    }
	    else {
		    unshift(@args, $arg);
		    last;
	    }
    }

    my $source_tree = "";
    my $dest_tree = "";

    # Get tree-ishes to compare
    if (scalar @args != 0 && $args[0] ne "--") {
        my $commit1 = shift(@args);

        if ($commit1 =~ m/^(.*)\.\.\.(.*)$/) {
            my $branch_2 = $2 == "" ? "HEAD" : $2;
            $source_tree = trim(safe_cmd("git merge-base $1 $branch_2"));
            $dest_tree = $2;
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
    return ($source_tree, $dest_tree, \%opts);
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

# Copies files from a named tree into a directory
# Parameters:
#     tree      - A tree-ish
#     file_list - A list ref giving a list of filenames to copy
#     out_dir   - The directory under which this tree should be reconstructed
sub copy_files_named_tree($$$) {
    (my $tree, my $file_list, my $out_dir) = @_;
    if (scalar @$file_list == 0) {
        return;
    }
    my $escaped_file_list = join(" ", map{shell_escape($_)} @$file_list);
    safe_cmd("cd \"\$(git rev-parse --show-toplevel)\" && git archive $tree $escaped_file_list | tar -x -C \"$out_dir\"");
}

# Links the files given as a list in the first argument from the working
# directory to the directory in the second argument
#
# These are linked rather than copied to allow the user to edit the files in the
# diff viewer
sub link_files_working_dir($$) {
    (my $file_list, my $out_dir) = @_;
    # Because we're diffing against the working directory we wish to create a
    # tree of links in the dest folder mirroring that in the repo.
    # TODO: Fix this so we don't have to loop over each filename somehow
    foreach my $filename (@$file_list) {
        my $dir = $filename;
        safe_system("mkdir", "-p", dirname("$out_dir/$filename"));
        safe_system("ln", "-s", cwd() . "/$filename", "$out_dir/$filename");
    }
}

# Copies the files given as a list in the first argument from the staging area
# to the directory in the second argument
sub copy_files_staging_area($$) {
    (my $filelist, my $outdir) = @_;
    safe_system("git", "checkout-index", "--prefix=$outdir/", "--", @$filelist);
}

my $all_args = join(" ", map{ shell_escape($_) } @ARGV);
(my $source_tree, my $dest_tree, my $opts) = parse_cmd(@ARGV);

if (exists($opts->{"cached"}) || exists($opts->{"staged"})) {
    ($dest_tree eq "") || die("Only one commit can be given with the option --cached.  You gave \"" . $dest_tree . "\"");
    if ($source_tree eq "") {
        $source_tree = "HEAD";
    }
}

# At this point we have parsed two commits and want to diff them
my $git_dir = trim(safe_cmd("git rev-parse --show-cdup"));
if ($git_dir eq "") {
	$git_dir = ".";
}

my $tmp_dir=trim(safe_cmd("mktemp -d -t git-meld.XXXXXX"));
my $source_dir  = "$tmp_dir/" . (($source_tree eq "") ? "staging_area" : $source_tree);
my $dest_dir = "$tmp_dir/" . (($dest_tree eq "") ? "working_dir" : $dest_tree);

safe_system("mkdir -p $source_dir");
safe_system("mkdir -p $dest_dir");

my $src_changed_files = nul_seperated_string_to_list(safe_cmd("git diff -z --diff-filter=DMTUXB --name-only $all_args"));
my $dest_changed_files = nul_seperated_string_to_list(safe_cmd("git diff -z --diff-filter=ACMTUXB --name-only $all_args"));

if ($source_tree eq "") {
    copy_files_staging_area($src_changed_files, $source_dir);
}
else {
    copy_files_named_tree($source_tree, $src_changed_files, $source_dir);
}

if (exists($opts->{"cached"}) || exists($opts->{"staged"})) {
    copy_files_staging_area($dest_changed_files, $dest_dir);
}
elsif ($dest_tree eq "") {
    link_files_working_dir($dest_changed_files, $dest_dir);
}
else {
    copy_files_named_tree($dest_tree, $dest_changed_files, $dest_dir);
}

safe_system("chmod", "-R", "a-w", "$tmp_dir/");

my $tool = get_config_or_default("treediff.tool", "meld");
my $cmd = get_config_or_default("treediff.$tool.cmd", $tool);
my $path = get_config_or_default("treediff.$tool.path", "");
safe_system("$path$cmd", "$source_dir", "$dest_dir");

safe_system("chmod", "-R", "u+w", "$tmp_dir/");
safe_system("rm", "-Rf", $tmp_dir);
