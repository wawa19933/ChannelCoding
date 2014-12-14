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
use IO::Poll qw(POLLIN POLLOUT POLLHUP); # Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw(SEEK_SET);			# Declaration of SEEK_SET flag for file seeking
use POSIX;						# For support of math functions

$\ = "\n";			# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;				# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $argc = @ARGV;				# Checking the number of arguments
if ($argc < 1) {				# If there is no arguments ->
	HELP_MESSAGE();				# 			print the help message
	exit;						# Exit
}

my $filePath = shift; 	     				# Taking the file's path from the FIRST argument
my $hostAddr = shift || 'localhost';		# Taking the server's address from the SECOND argument
my $port = '8849';							# Variable for port number defenition
my $filename = fileparse ( $filePath );		# Extracting the name of the file
my ( $buffer, $counter, $partsCount, @arq ); 	# Some global variables
my $sz = 1024;								# Definding of packet portion for transmittion
my $fileSize = -s $filePath;				# Taking the size of the local file (-s is a size operator)
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

$counter = 0;								# Initialization of the counter for transmitions' number
$partsCount = ceil ( $fileSize / $sz );		# Number of packets to be sent
# 1) --	Sending the file name to server	#################################
while ( $counter != 3 ) {					# Loop for 3times file information transmition
  my @msg = ( 'NAME', $partsCount, $filename, $fileSize );			# Forming of the message
  $socket->send ( join ( ';', @msg ) ) or die "Sending error: $!";	# Sending of the prepared message
  $counter ++;								# Increment the counter
}

$counter = 0;								# Initialization of the counter for packet numbering
print "Filename is sent, starting to send the file...";
# 2) --	Sending the whole file by parts of $sz Bytes size
while ( read ( FILE, $buffer, $sz ) > 0 ) {		# This loop performs reading the file untill the end of it
	my $res = sendData ( $buffer );			# Sending the prepared data
	print "$counter) $res bytes are sent to $hostAddr";
}

my $stop = 1;								# A flag for breaking the loop of ARQ processing
print "\n============ Processing ARQ... ==========";
while ( $stop ) {							# Untill we mark it for stop
	$socket->send ( 'CHECK' );	# 
	$stop = checkForPackets ();	#
}

print "\nThe end\n";

close FILE;       		# Closing the file
close $socket;			# Closing the socket 

sub sendData {								# Function for file parts transmition
	my $rawData = shift;					# Parameter of the function is data from file
	my $encoded; 							# Variable for Base64 encoded data
	
	$counter ++;							# Increment of the counter for packets numbering
	$encoded = encode_base64 ( $rawData );	# Encoding of the file data
	my @msg = ( 'DATA', $counter, $encoded ); # Forming the message
	
	return $socket->send (join ';', @msg );	# Send the message
}

sub checkForPackets {						#
	my $check = IO::Poll->new;				# Creating an object for poll() call
	$check->mask ( $socket => POLLIN )		# and watching for incoming data
	
	while ( ) {								#
		if ( $check->poll (100) ) {			# checking for the incoming ARQ in receiving 
			$socket->recv ( $buffer, 255 );	#
			my @packet = split ';', $buffer;#
			my $cmd = shift @packet;		#
			my $num = shift @packet;		#
			my $left = pop @packet;			#
			
			if ( $cmd eq 'ARQ' ) {			#
				print "Server has not got $num/$left packets";
				push @packet, $num;			#
			}
			if ( $cmd eq 'FINISH' ) {		#
				foreach $num ( @arq ) {		#
					repeatPart ( $num );	#
				}
			}
			if ( $cmd eq 'EXIT' ) {			#
				$socket->send ( 'EXIT' );	#
				return 0;					#
			}
		}
	}
}

sub repeatPart {							#
	my $num = shift;						#
	my $pos = tell FILE;					#
	
	if ( seek ( FILE, $num * $sz, SEEK_SET ) ) {
		if ( read ( FILE, $buffer, $sz ) > 0 ) {
			print sendData ( $buffer ) . " bytes of $num ARQ are re-sent to $hostAddr";
		}
	}
	seek ( FILE, $pos, SEEK_SET );
}

sub HELP_MESSAGE {
	print "\nUsage: client.pl [file] [host] \n";
}
