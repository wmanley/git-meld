#!/usr/bin/perl

# git diff [<common diff options>] <commit>{0,2} [--] [<path>...]
# git archive [--format=<fmt>] [--list] [--prefix=<prefix>/] [<extra>]
#              [-o | --output=<file>] [--worktree-attributes]
#              [--remote=<repo> [--exec=<git-upload-archive>]] <tree-ish>
#              [path...]

use strict;

my $diff_opts = "";
my $source_tree = "";
my $dest_tree = "";

my $all_args = "\"" . join("\" \"", @ARGV) . "\"";

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

# Get options to be sent to diff
while (my $arg = shift(@ARGV)) {
	if ($arg =~ m/^-/ && $arg != "--") {
		$diff_opts += " \"$arg\"";
	}
	else {
		unshift(@ARGV, $arg);
		last;
	}
	if ($arg == "--cached") {
		die ("--cached option not supported");
	}
}

# Get tree-ishes to compare
if (scalar @ARGV == 0 || $ARGV[0] eq "--") {
	safe_cmd("meld ./");
	exit(0);
}

my $commit1 = shift(@ARGV);

if ($commit1 =~ m/^(.*)\.\.\.(.*)$/) {
	$source_tree = trim(safe_cmd("git merge-base $1 $2"));
	$dest_tree = $2;
	shift(@ARGV);
}
elsif ($commit1 =~ m/^(.*)\.\.(.*)$/) {
	$source_tree = $1;
	$dest_tree = $2;
}
else { 
	$source_tree = $commit1;
	if (scalar @ARGV == 0) {
	}
	else {
		my $commit2 = shift(@ARGV);
		if ($commit2 ne "--") {
			$dest_tree = $commit2;
		}
	}
}

if ($dest_tree eq "") {
	die("Diff to working directory not yet implemented!");
}

# Can ignore any paths as git diff should take care of that for us

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

safe_cmd("meld $source_dir $dest_dir");

system("rm -R $tmp_dir");
