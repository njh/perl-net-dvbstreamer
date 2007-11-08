#!/usr/bin/perl
#
# dvbwebctrl.pl
# =============
#
# A HTTP server written in perl to remote control
# a DVBStreamer server.
#
# By Nicholas Humfrey <njh@aelius.com>
#
#
# Required Debian Packages:
#
# libwww-perl
# libhtml-parser-perl
# liburi-perl
#


use HTTP::Daemon;
use HTTP::Request;
use HTTP::Status;
use HTML::Entities;
use URI::Escape;
use Data::Dumper;
use Net::DVBStreamer::Client;

use strict;
use warnings;




## Start of Settings ##
my $DEBUG = 1;

my $HTTP_Host = '10.63.83.20';
my $HTTP_Port = 8080;
my $HTTP_Queue = 5;

my $DVBS_Host = '127.0.0.1';
my $DVBS_User = 'dvbstreamer';
my $DVBS_Pass = 'chipmonk';
my $DVBS_Adaptor = 0;


my @ALLOW_HOSTS = (
	'127.0.0.1',	# localhost
	'10.63.83.25',
	'10.63.83.15',
);

## End of Settings ##






# Version Number
my $VERSION = "0.1";

# Force Hot output
$|=1;







# Create the HTTP Daemon
my $d = HTTP::Daemon->new(
 	LocalAddr=>$HTTP_Host,	# Address to listen on
 	LocalPort=>$HTTP_Port,	# Port to listen on
 	Listen=>$HTTP_Queue,	# Queue size
 	Reuse=>1 ) || die;


log_print( "HTTP Daemon started on $HTTP_Host:$HTTP_Port" );


while (my $c = $d->accept) {
	my $r = $c->get_request;
	
	log_print( "Handling request from ".$c->peerhost()." for ".$r->url );

	# Is the host authorised ?
	if (!grep($c->peerhost() eq $_, @ALLOW_HOSTS)) {
		print "Host isn't authorised: ".$c->peerhost()."\n";
		$c->send_error(RC_FORBIDDEN);
		
	} else {
	
		# We only handle GET requests
		if ($r->method ne 'GET') {
			print "Method isn't implemented: ".$r->method()."\n";
			$c->send_error(RC_NOT_IMPLEMENTED);
		
		} else {
			if ($r->url->path eq "/") {
				# Just redirect to the channel list
				my $response = HTTP::Response->new( RC_FOUND );
				$response->header( 'location' => '/list' );
				$c->send_response( $response );
			}
			
			elsif ($r->url->path eq "/list") { handle_channel_list( $c, $r->url->query ); }
			elsif ($r->url->path eq "/select") { handle_channel_select( $c, $r->url->query ); }
	#		elsif ($r->url->path eq "/status.xml") { handle_xml_request( $c ); }
	
			else {
				$c->send_error(RC_NOT_FOUND);
			}
		}
	
	}

	$c->close;
	undef($c);
}

$d->close();




sub handle_channel_list {
	my ($client, $query) = @_;


	my $dvbs = connect_dvbs();
	my @channels = $dvbs->send_command( 'lslcn' );

	if (scalar(@channels)) {
	
		## Success
		my $response = HTTP::Response->new( RC_OK );
		$response->content_type('text/html');
		my $content = create_html_header("Channel List");
		foreach my $channel ( @channels ) {
			my ($num, $name) = ($channel =~ /(\d+)\s:\s(.+)/);
			my $href = "/select?".uri_escape($name);
			$content .= "$num. <a href='$href'>".encode_entities($name)."</a><br />\n";
		}
		$content .= create_html_footer();
		$response->content( $content );
		$client->send_response( $response );
		
	} else {
	
		## Error
		#handle_dvbs_error( $client, $dvbs );

	}
	
}


sub handle_channel_select {
	my ($client, $query) = @_;
	my $channel = uri_unescape( $query );

	my $dvbs = connect_dvbs();
	my $result = $dvbs->send_command( 'select', $channel );
	log_print("Sending command: select $channel: $result" );
	
	if (defined $result and $dvbs->response() eq 'OK') {
		my $response = HTTP::Response->new( RC_OK );
		$response->header('Refresh' => '1; url=/list'); # Redirect after a second
		$response->content_type('text/plain');
		$response->content( "Selected: ".$channel );
		$client->send_response( $response );
	
	} else {
	
		## Error
		handle_dvbs_error( $client, $dvbs );

	}
}


sub handle_dvbs_error {
	my ($client, $dvbs) = @_;

	my $response = HTTP::Response->new( RC_INTERNAL_SERVER_ERROR );
	$response->content_type('text/plain');
	$response->content( "Internal Server error: ".$dvbs->response() );
	$client->send_response( $response );
}

sub connect_dvbs {

	my $dvbs = new Net::DVBStreamer::Client( $DVBS_Host, $DVBS_Adaptor );
	
	if (defined $DVBS_User and defined $DVBS_Pass) {
		if (!$dvbs->authenticate( $DVBS_User, $DVBS_Pass )) {
			die "Failed to authenticate with server: ".$dvbs->response()."\n";
		}
	}

	return $dvbs;
}

sub create_html_header {
	my $title = shift;
	my $content = '';
	
	$content .= '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"';
    $content .= '  "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">';
	$content .= '<html><head><title>'.$title.'</title></head>';
	$content .= '<body bgcolor="#ffffff"><H1>'.$title.'</H1>';

	return $content;
}


sub create_html_footer {
	my $content;
	
	$content .= '<hr /><I>dvbwebctrl.pl version '.$VERSION;
	$content .= ' by Nicholas J Humfrey</I>';
	$content .= '</body></html>';
	
	return $content;
}


sub log_print {
	my ($msg) = @_;
	
	if ($DEBUG) {
		print localtime().": $msg\n";
	}
	
}



# sub handle_status_request {
# 	my $client = shift;
# 	my $response = HTTP::Response->new( RC_OK );
# 
# 	my $content = create_html_header('ino711d: Status');
# 	$content .= '<table border="1" cellspacing="0" cellpadding="2">';
# 
# 	my $c=0;
# 	foreach my $key (keys %$rds_field_map) {
# 		my $field = $rds_field_map->{$key};
# 		
# 		if ($c%2)	{ $content .= '<TR bgcolor="#f5f5ff">'; }
# 		else		{ $content .= '<TR bgcolor="#ffffff">'; }
# 		
# 		$content .= "<TD><B>".$key."</B><BR>";
# 		$content .= "<FONT SIZE='-1'>".$field->{'name'}."</FONT></TD>";
# 		
# 		$content .= '<TD>'.$field->{'value'};
# 		if ($field->{'type'} eq 'enum') {
# 			$content .= " (".$field->{'enum'}->{$field->{'value'}}.")";
# 		}
# 		$content .= '</TD><td width="50" align="center">';
# 		
# 		$content .= '<A HREF="/edit?'.$key.'">Edit</A>'
# 		unless (defined $field->{'ro'});
# 		
# 		$content .= '</TD></TR>';
# 		$c++;
# 	}
# 
# 	$content .= '</TABLE></FORM><BR><BR>';
# 	$content .= 'This information is also available as XML ';
# 	$content .= '<A HREF="/status.xml">here</A>.';
# 	$content .= create_html_footer();
# 
# 	$response->content( $content );
# 	$response->content_type('text/html');
# 	$client->send_response( $response );
# }



__END__


=head1 NAME

dvbwebctrl - Web/HTTP based control interface for DVBStreamer

=head1 DESCRIPTION

dvbwebctrl is a completely self-contained perl script, with built-in web server, making it very easy to configure and deploy.

=head1 README

This script is a Web/HTTP based control interface for DVBStreamer.

=head1 PREREQUISITES

This script requires the modules from the C<libwww-perl> package.

=pod OSNAMES

Linux

=pod SCRIPT CATEGORIES

Web
Misc

=head1 AUTHOR

Nicholas J Humfrey E<lt>njh@cpan.orgE<gt>

=head1 COPYRIGHT

    Copyright (c) 2007, Nicholas J Humfrey. All Rights Reserved.
    This module is free software. It may be used, redistributed
        and/or modified under the same terms as Perl itself.

=cut

