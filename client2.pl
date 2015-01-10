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
use String::CRC32;

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
my $srvPort = '8850'
my $fileName = fileparse ( $filePath );		# Extracting the name of the file
my $blockSize = 4096;						# Definding of packet portion for transmittion
my $fileSize = -s $filePath;				# Taking the size of the local file (-s is a size operator)
my $windowSize = 80;						# ARQ Window size 
my $timeout = 0.7;
my $delim = ';';
my ( $buffer, $number, $partsCount, @arq, @msg ); # Some global variables
my ( $dataSocket, $serviceSocket );
print "Going to send $fileName to $hostAddr";	

#	Opening the specified file in BINARY form for reading only
open FILE, '<', $filePath or die "Can not open the file!!! $filePath: $!";
binmode FILE;

#	Creating the UDP socket for file parts transmitting with specified host
$dataSocket = IO::Socket::INET->new (
		PeerAddr 	=> $hostAddr,
		PeerPort 	=> $port,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM,
		Timeout 	=> 100
	) or die "Couldn't create UDP socket!!!: $!";

$serviceSocket = IO::SOCKET::INET->new (
		PeerAddr	=> $hostAddr,
		PeerPort	=> $srvPort,
		Proto 		=> 'tcp',
		Type		=> SOCK_STREAM,
		Timeout 	=> 100
	) or die "Couldn't create TCP socket! : $!";

$number = 0;								# Initialization of the counter for transmitions' number
$partsCount = ceil ( $fileSize / $sz );		# Number of packets to be sent

#	1)	---	Sending info
$serviceSocket->send ( join $delim, ( 'INFO', $number, $fileName, $fileSize ) );

#	2)	---	Sending file
while ( !eof(FILE) ) 
{
	for ( $i = 0; $i < $window; $i++ ) 
	{
		my $bytes = read ( FILE, $buffer, $blockSize ) || 
					die "Error during file reading : $!";
		
		$number ++;
		@msg = ($number, encode_base64 ( $buffer ));

		$bytes = $dataSocket->send ( join ($delim, @msg) ) || 
					die "Error during sending : $!";
	}

	#	3)	---	Checking
	getARQ();
	foreach $n (@arq)
	{
		repeatPart ( $n ) or 
			die "Can not resend $n : $!";
	}

	# while ( !checkReceive (0.110) )
	# {
	# 	$socket->send ( 'WINDOW' );
	# }
	# $socket->recv ( $buffer, $blockSize );
	# my @msg = split $delim, $buffer;
	# my $cmd = shift @msg;
	# my @parts = split ( ',', shift @msg );
	# foreach $num ( @parts ) {
	# 	if (repeatPart ( $num ) > 0) {
			
	# 	}
	# }
}

my $crc = crc32 ( *FILE );
$serviceSocket->send ( join ($delim, ('CHECK', $crc)) );
$serviceSocket->recv ( $buffer, 4000 );
if ($buffer eq 'OK') {
	print "File had been sent successfully!";
}
else {
	print "Check had been failed!";
} 

# DEBUG
print "File had been sent"; 

close FILE;
close $dataSocket;
close $serviceSocket;
################################################################

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

sub getARQ {
	undef @arq;
	my $bytes = $serviceSocket->read ( $buffer, 7000 ) or 
		die "Can not read the service TCP socket! : $!";

	my @message = split $delim, $buffer;
	my $cmd = shift @message;

	if ($cmd eq 'ARQ') {
		@arq = split (':', shift ( @message ));
	}

	# DEBUG
	print "\nARQ list: @arq"; 
}

sub repeatPart {
	my $num = shift;

	# DEBUG
	print "\t- $num Repeat is started...";

	open FH, '<', $filePath or 
		die "Open file for repeat the part error : $!";
	seek ( FH, $num * $blockSize, 0 );
	read ( FH, $buffer, $blockSize ) or
		die "Read the part for repeat error : $!";

	my $res = $socket->send ( ('DATA', $num, encode_base64($buffer)) ) or
		die "Send the repeat part error : $!";
	
	# DEBUG
	print "\t- $num Repeat is finished! $res bytes";

	return $res;
}