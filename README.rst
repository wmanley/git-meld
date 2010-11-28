===============
git meld README
===============

SYNOPSIS
========
    git meld [options] <commit>{0,2} [--] [<path>...]

DESCRIPTION
===========
    git meld is a git command that allows you to compare and edit treeishs
    between revisions using meld or any other diff tool that supports directory
    comparison.  git meld is a frontend to git diff and accepts the same options
    and arguments.

    It is essentially an extended git-difftool for tools that support comparing
    directories rather than having git call the external tool for every file
    that has changed

EXAMPLE
=======

    Show the differences between the staging area and your working directory:
        $ git meld
    
    Show the differences between HEAD and the staging area (i.e. what would be
    commited if you were commit now:
        $ git meld --cached
    
    Show the differences between two commits ago and the working directory:
        $ git meld HEAD^^
    
    Show the differences between the tips of branch master and branch topic
        $ git meld master..topic
    
    Show all the changes made to branch topic since it branched off branch
    master
        $ git meld master...topic

INSTALLATION
============
    Add a git alias to your gitconfig with:
        $ git config --global alias.meld \!/path/to/git-meld/git-meld.pl

    Alternatively add:

        [alias]
        	meld = !/path/to/git-meld/git-meld.pl
    
    To your ~/.gitconfig

CONFIGURATION
=============
    The following additional git configuration variables are available for
    setting up git meld for using diff tools other than meld:
    
       treediff.tool
           Controls which diff tool is used.

       treediff.<tool>.path
           Override the path for the given tool. This is useful in case your
           tool is not in the PATH.

       treediff.<tool>.cmd
           Specify the command to invoke the specified diff tool.

CONTACT
=======
    git repo, bug tracker and wiki for git meld are available on github at
    https://github.com/wmanley/git-meld

HOW IT WORKS
============
    git meld uses "git diff --name-only" to extract the files that have changed
    between the two commits and then makes a copy of these files into a
    temporary directory before invoking meld on these copies.

