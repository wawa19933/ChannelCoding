#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				 __________________________________	#
#		Packet structure:	| command | number | data | [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#################################################################
use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use Digest::CRC qw( crc64 crc32 crc ); # Module for CRC calculation
use IO::Poll qw(POLLIN POLLOUT POLLHUP); # Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw(SEEK_SET);

$\ = "\n";						# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;							# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $argc = @ARGV;				# Checking the number of arguments
if ($argc < 1) {
	HELP_MESSAGE();
	exit;
}

my $filePath = shift; 	     			# Taking the file's path from the FIRST argument
my $hostAddr = shift || 'localhost';	# Taking the server's address from the SECOND argument
my $port = '8849';						# Variable for port number defenition
my $filename = fileparse ( $filePath );	# Extracting the name of the file
my ( $buffer, $counter, @arq ); 	# Some global variables
my $sz = 1024;
my $fileSize = -s $filePath;
print "Going to send $filename to $hostAddr";

#	Opening the specified file in BINARY form for reading only
open FILE, '<', $filePath or die "Can not open the file!!! $filePath: $!";
binmode FILE;

#	Creating the UDP socket for communication with specified host
my $socket = IO::Socket::INET->new(
				PeerAddr 	=> $hostAddr,
				PeerPort 	=> $port,
				Proto 		=> 'udp',
				Type		=> SOCK_DGRAM
	) or die "Couldn't create socket!!!: $!";


# 1) --	Sending the file name to server	#################################
$counter = 0;
my @msg = ( 'NAME', $counter, $filename, $fileSize );
$socket->send ( join ';', @msg ) or die "Sending error: $!";

# 2) --	Sending the whole file by parts of $sz Bytes size
while ( read FILE, $buffer, $sz > 0 ) {						# This loop performs reading the file untill the end of it
	my $res = sendData ( $buffer );
	print " $res bytes are sent to $hostAddr";				# sending the prepared data
}

print "\nThe end\n";

close FILE;       # Closing the file

sub HELP_MESSAGE {
	print "\nUsage: client.pl [file] [host] \n";
}

sub sendData {
	my $rawData = shift;					# Parameter of the function is data from file
	my ( $encoded, $hash ); 
	
	$counter ++;
	$hash = crc32 ( $rawData );
	$encoded = encode_base64 ( $rawData );
	
	my @msg = ( 'DATA', $counter, $encoded, $hash );
	
	return $socket->send (join ( ';', @msg ));
}

sub repeatSending {
	my ( $cmd, $num, $data ) = @_;
	my $pos = tell FILE;
	
	if ( seek FILE, $num * $sz, SEEK_SET ) {
		if ( read FILE, $buffer, $sz > 0 ) {
			print sendData ( $buffer ) . " bytes of $num ARQ are re-sent to $hostAddr";
		}
	}
	
	seek FILE, $pos, SEEK_SET;
}

sub checkForPackets {
	my $check = IO::Poll->new;					# Creating an object for poll() call
	$check->mask ( $socket => POLLIN );			# and watching for incoming data

	if ( $check->poll (15) ) {										# checking for the incoming ARQ in receiving 
		my $arqMsg;
		$socket->recv ( $arqMsg, 255 );
		my @packet = split ';', $arqMsg;
		
		repeatSending (@packet);
	}
}