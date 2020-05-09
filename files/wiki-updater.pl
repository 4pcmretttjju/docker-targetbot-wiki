#!/usr/bin/perl -w

use strict;
use warnings;

use HTML::TreeBuilder -weak; # Ensure weak references in use (no need to call $tree = $tree->delete; when done)
use MediaWiki::API;

################################################################################
# Input paratemers are hard coded or read from VM environment values
################################################################################
my $wikiuser = 'TargetReport';			# Wiki pages to update, e.g. 
										# http://wiki.urbandead.com/index.php/User:TargetReport/Ridleybank
my $wiki_dir = "$wikiuser";

################################################################################
# Parse wiki username and password from VM environment values, e.g.
# "MapBot,as87sfsdASF8908asfAS898098asfasa"
################################################################################
my @wiki_login = split(',', $ENV{'WIKI_LOGIN'});
my $wiki_login = $wiki_login[0];
my $wiki_password = $wiki_login[1];

################################################################################
# Create the MediaWiki instance.
################################################################################
my $udwikiapi = MediaWiki::API->new();
if (!$udwikiapi) {die "Failed to create new MediaWiki instance."}
$udwikiapi->{config}->{api_url} = 'http://wiki.urbandead.com/api.php';

################################################################################
# Now loop forever, checking the specified directory for updates each second.
################################################################################
while (sleep(1)) 
{
	################################################################################
	# Read the directory, and loop through the filename list (if any).
	################################################################################
	opendir (DIR, $wiki_dir) or die $!;

	while (my $filename = readdir(DIR)) {

		################################################################################
		# Open the current file and read contents into an array.  Ignore empty files.
		################################################################################
		open( my $input_fh, "<", "$wiki_dir/$filename" ) || next;	# Ignore empty files.
		my @file_data = <$input_fh>;	# Create an array - one entry per line
		close ($input_fh); 			# Close the file 

		################################################################################
		# Now remove the file.  Skip to the next file if this fails for any reason.
		################################################################################
		unlink ("$wiki_dir/$filename") || next;
		
		################################################################################
		# Now build the new page from the contents of the file we just read.
		# - First line contains the description to use.
		# - The rest of the file contains the page contents.
		################################################################################
		my $summary = shift(@file_data);
		my $newpage = '';

		for (@file_data) {
			$newpage .= $_;
		}
		chomp ($newpage);		# Wiki always ignores any trailing newlines.

		################################################################################
		# Read the wiki page we're interested in changing.
		################################################################################
		my $pagename = "User:$wikiuser/$filename";

		my $page = $udwikiapi->get_page( { title => $pagename } );
		if (!($page) || $page->{missing}) {next}

		################################################################################
		# Skip to the next file if the contents haven't changed.
		################################################################################
		if ($newpage eq $page->{'*'}) {next}
	
		################################################################################
		# Now update the wiki page with the new text.
		################################################################################
		print "Updating wiki page: $pagename \n";

		update_wiki_page($pagename, $page->{timestamp}, $newpage, $summary) || next;

		################################################################################
		# If we got this far, pause for a second before updating another page.
		################################################################################
		sleep(1);
	}

	closedir(DIR);
}

################################################################################
# update_wiki_page()
#
# - Updates the specified wiki page with specified text.
# - Automatically logs in (or updates login token) if required.
# - Returns error text, or empty string if successful.
################################################################################
sub update_wiki_page 
{
	my $pagename =	$_[0];		# Wiki pagename e.g. User:TargetReport/RRF
	my $timestamp =	$_[1];		# Fom the original $page->{timestamp}
	my $newpage = 	$_[2];		# New page contents		
	my $summary =	$_[3];		# Description of change

	################################################################################
	# Try updating the wiki page using existing login credentials first.  This 
	# reduces the risk of throttling errors (logins are rate-limited to 1 /minute).
	################################################################################		
	my $rc = $udwikiapi->edit( {
		action => 'edit',
		bot => '1',
		title => $pagename,
		basetimestamp => $timestamp, # to avoid edit conflicts
		text => $newpage,
		summary => $summary,
	} );

	################################################################################
	# $udwikiapi->edit() returns 'true' if successful.  Otherwise log and handle 
	# the error, which is stored in $udwikiapi->{error}->{code}.
	################################################################################		
	if (!$rc)
	{			
		debug_log (wiki_error($udwikiapi, __LINE__));

		################################################################################
		# Try logging in if we got one of the following relevant error codes:
		#
		# 	3: bad login token	(login expired)
		# 	5: not logged in 	(first update since starting bot)
		################################################################################		
		if (($udwikiapi->{error}->{code} == 3) || ($udwikiapi->{error}->{code} == 5))
		{
			################################################################################
			# First log out if required (for bad token erros), and then log in again.
			################################################################################		
			debug_log ("Logging in as $wiki_login...");
			$udwikiapi->logout() if ($udwikiapi->{error}->{code} == 3);
			$udwikiapi->login( { lgname => $wiki_login, 
						lgpassword => $wiki_password } ) || return wiki_error($udwikiapi, __LINE__);

			################################################################################
			# Now re-attempt the page update (once only).
			################################################################################		
			$udwikiapi->edit( {
				action => 'edit',
				bot => '1',
				title => $pagename,
				basetimestamp => $timestamp, # to avoid edit conflicts
				text => $newpage,
				summary => $summary,
				} ) || return wiki_error($udwikiapi, __LINE__);
		}
		else {return wiki_error($udwikiapi, __LINE__)}
	}
}

sub wiki_error
{	
	my $udwikiapi = $_[0];		
	my $line_number = $_[1];
	return "ERROR: line $line_number: (" . $udwikiapi->{error}->{code} . ") " . $udwikiapi->{error}->{details};
}

sub debug_log
{
	my $log_text = $_[0];
	print "$log_text \n";
}
