#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_________________________________	#
#		Packet structure:  | command | number | data | [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#################################################################
use strict;
use warnings;

use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
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
my $fileName = fileparse ( $filePath );		# Extracting the name of the file
my ( $buffer, $number, $partsCount, @arq ); # Some global variables
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $fileSize = -s $filePath;				# Taking the size of the local file (-s is a size operator)
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;
my $delim = ';';
print "Going to send $fileName to $hostAddr";	

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

$number = 0;								# Initialization of the counter for transmitions' number
$partsCount = ceil ( $fileSize / $sz );		# Number of packets to be sent

#	1)	---	Sending info
my @infoMsg = ( 'INFO', $number, $fileName, $fileSize );
$socket->send ( join $delim, @infoMsg );

#	2)	---	Sending file
while ( !eof(FILE) ) 
{
	for ( $i = 0; $i < $window; $i++ ) {
		my $bytes = read ( FILE, $buffer, $blockSize ) || 
					die "Error during file reading : $!";
		my $encoded = encode_base64 ( $buffer );
		$number ++;
		my @msg = ('DATA', $number, $encoded);

		$bytes = $socket->send ( join (';', @msg) ) || 
					die "Error during sending : $!";
	}

	while ( !checkReceive (0.110) )
	{
		$socket->send ( 'WINDOW' );
	}
	$socket->recv ( $buffer, $blockSize );
	my @msg = split $delim, $buffer;
	my $cmd = shift @msg;
	my @parts = split ( ',', shift @msg );
	foreach $num ( @parts ) {
		if (repeatPart ( $num ) > 0) {
			
		}
	}
}

#	3)	---	Checking

sub checkReceive {
	my $time = shift || $timeout;
	my $poll = IO::Poll->new;
	$poll->mask ( $socket => POLLIN );
	my $result = $poll->poll ( $time );

	if ( $result == -1 ) {
		print "Error with poll() : $!";
		return 0;
	}

	return $result;
}

sub repeatPart {
	my $num = shift;
	print "\t- $num Repeat is started...";
	open FH, '<', $filePath || die "Open file for repeat the part error : $!";
	seek ( FH, $num * $blockSize, 0 );
	read ( FH, $buffer, $blockSize ) || die "Read the part for repeat error : $!";

	my $res = $socket->send ( ('DATA', $num, encode_base64($buffer)) ) || "Send the repeat part error : $!";
	print "\t- $num Repeat is finished!";

	return $res;
}