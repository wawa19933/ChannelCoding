#!/usr/bin/perl
#################################################################
# 	Title	:	UDP Client script								# 
#	Authors	: 													#
#	Description:												#
#																#
#		 	 				_________________________________	#
#		Packet structure:  | number |	   data 	|  [CRC] |	#
#						    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾	#
#		MTU(Ethernet) = 1500 bytes 								#
#		MSS			  = 1460 bytes (MTU without headers TCP/IP) #
#################################################################
# use strict;
# use warnings;

use String::CRC32;				# Module for CRC32 calculation function
use IO::Socket::INET;         	# Module that adds the socket support
use File::Basename;				# Module for extracting file name from the path
use MIME::Base64;				# Module for encoding binary data
use POSIX;						# For support of math functions
use Term::ProgressBar;			# Console progressbar
use IO::Poll qw( POLLIN ); 		# Module for ARQ realization: for data detection in a receiving buffer
use Fcntl qw( SEEK_SET );		# Declaration of SEEK_SET flag for file seeking
use Digest::MD5 qw( md5_hex md5_base64 );
use Time::HiRes qw( gettimeofday tv_interval );

$\ = "\n";			# Added as an invisible last element to the parameters passed to the print() function. *doc
$| = 1;				# If nonzero, will flush the output buffer after every write() or print() function. Normally, it is set to 0. *doc
				
my $filePath = shift; 	     					# Taking the file's path from the FIRST argument
my $hostAddr = shift || 'localhost';			# Taking the server's address from the SECOND argument
my $udpPort = '8849';							# Variable for port number of the UDP socket for data transmission
# my $tcpPort = '8850';							# Port for TCP connection for service info exchange
my $fileName = fileparse ( $filePath );			# Extracting the name of the file
my $fileSize = -s $filePath;					# Taking the size of the local file (-s is a size operator)
my $blockSize = 1024;							# Definding of packet portion for transmittion
my $delim = ';';								# Global delimiter for packets' fields
my ( $buffer, $number, $partsCount); 			# Some global variables
my ( $udpSocket, $tcpSocket );					# Global
my ( $totalBytes, $totalPackets, $totalTime, $lossCount ); # Global
###	END of declarations
#------------------------------------------------------------------------------------------------------------------------------------
print "\n--> Going to send $fileName ($fileSize bytes) to $hostAddr...\n";	
#------------------------------------------------------------------------------------------------------------------------------------
#	Opening the specified file in BINARY form for reading only
# open FILE, '<', $filePath or die "Can not open the file!!! $filePath: $!";
# binmode FILE;
#------------------------------------------------------------------------------------------------------------------------------------
#	Creating a UDP socket for file parts transmission to the specified host
$udpSocket = IO::Socket::INET->new (
		PeerAddr 	=> $hostAddr,
		PeerPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM
	) or die "Couldn't create UDP socket!!!: $!";

# #	Creating a TCP socket for service info transmission
# $tcpSocket = IO::Socket::INET->new (
# 		PeerAddr	=> $hostAddr,
# 		PeerPort	=> $tcpPort,
# 		Proto 		=> 'tcp',
# 		Reuse 		=> 1,
# 		Type		=> SOCK_STREAM
# 	) or die "Couldn't create TCP socket! : $!";
readFile ();
$partsCount = ceil ( $fileSize / $blockSize );
$number = 0;											# Initialization of the counter for transmitions' number
$totalTime = 0;
$totalPackets = 0;
$totalBytes = 0;
# my $progressBar = Term::ProgressBar->new ( $fileSize ); # Initialization of a progress bar with the size of the file
#------------------------------------------------------------------------------------------------------------------------------------
#	1)	---	Sending a file info 
# my $ck = Digest::MD5->new ();
# $ck->addfile ( FILE );
sendWithACK ( join ($delim, ( 'INFO', $fileName, $fileSize, $blockSize, md5_hex( join ('', @file) ) )), 2 );
# seek FILE, 0, 0;
#------------------------------------------------------------------------------------------------------------------------------------
my $t0 = [gettimeofday];
#------------------------------------------------------------------------------------------------------------------------------------
# while ( !eof ( FILE ) ) 
# {
# 	my $bytes = read ( FILE, $buffer, $blockSize ) or 		# Reading the $blockSize bytes from the file
# 				die "Error during file reading : $!";

# 	if ( $bytes lt $blockSize ) {
# 		print "Read from file: $bytes / $blockSize bytes";
# 	}
# 	push @file, $buffer;
	
# 	$number ++;
# 	$bytes = $udpSocket->send ( join ( $delim, ('DATA', $number, encode_base64 ( $buffer ), md5_hex ( $buffer )) ) ) or 
# 				die "Error during sending : $!"; 	# Sending the Base64 encoded part of the file and checksum for this part

# 	$progressBar->update ( tell FILE );
# 	$totalBytes += $bytes;
# 	$totalPackets ++;
# }
my $progressBar = Term::ProgressBar->new ( $partsCount+1 ); # Initialization of a progress bar with the size of the file

for ( my $c = 0; $c < $partsCount; $c++ ) {
	my $bytes = $udpSocket->send (join ( $delim, ('DATA', $c+1, encode_base64 ( $file[ $c ] ), md5_hex ( $file[ $c ] )) ) ) or
				die "Error while send : $!";
	$progressBar->update ( $c );
	$totalBytes += $bytes;
	$totalPackets ++;
}

#------------------------------------------------------------------------------------------------------------------------------------
# sendWithACK ( 'END' );
#------------------------------------------------------------------------------------------------------------------------------------
#	2.2) -- Checking and repeating
my $ack = 'KO';
while ( $ack ne 'OK' )
{
	$udpSocket->send ('CHECK');
	if ( checkIncomingUDP ( 2 ) > 0 ) {
		print "CheckIncomingUDP()";
	 	$udpSocket->recv ( $buffer, 5000 );

		my @msg = split $delim, $buffer;
		$ack = shift @msg;
		my @arq = split (':', shift ( @msg ));
		
		if ( @arq ) {
			print "ACK: $ack ";
			foreach my $n ( @arq ) {
				repeatPart ( $n );
			}
		}
	 }
}
#------------------------------------------------------------------------------------------------------------------------------------
# FINISHING
#------------------------------------------------------------------------------------------------------------------------------------
$totalTime = tv_interval ( $t0 );
$udpSocket->send ( join $delim, ('FINISH', $totalTime, md5_hex( join ( '', @file )), $totalBytes, $totalPackets) );

print "\n--> File is transfered!";
my $sss = $totalBytes - $fileSize;
print "Total: $totalBytes ($sss) bytes in $totalPackets packets. During $totalTime seconds\n";

print "MD5(array): ". md5_hex ( join ( '', @file ) );
# print "MD5(file) : ". Digest::MD5->new()->addfile ( FILE )->hexdigest;

sub sendWithACK {
	my $data = shift;
	my $timeout = shift or 1.1;
	my $ack = 'KO';
	my $poll = IO::Poll->new ();
	$poll->mask ( $udpSocket => POLLIN );
	while ( $ack ne 'OK' ) {
		$udpSocket->send ( $data );
		if ( $poll->poll ( $timeout ) > 0 ) {
			$udpSocket->recv ( $ack, 5 );
		}
	}
}

sub repeatPart {
	my $num = shift;

	open FH, '<', $filePath or 
				die "Open file for repeat the part error : $!";
	seek ( FH, $num * $blockSize, 0 );
	read ( FH, $buffer, $blockSize ) or
				die "Read the part for repeat error : $!";

	# my $res = $udpSocket->send ( join ( $delim, ('REPEAT', $num, encode_base64($buffer), md5_hex ($buffer)) ) ) or
	# 			die "Send the repeat part error : $!";
	$udpSocket->send (join ( $delim, ('DATA', $num, encode_base64 ( $file[ $num-1 ] ), md5_hex ( $file[ $num-1 ] )) ) ) or
				die "Error while send : $!";

	return $res;
}

sub checkIncomingUDP {
	my $timeout = shift or 1.1;
	my $poll = IO::Poll->new ();
	$poll->mask ( $udpSocket => POLLIN );

	return $poll->poll ($timeout);
}

sub readFile {
	open $fh, "<", $filePath;

	while ( not eof ($fh) ) {
		my $bytes = read ( $fh, $buffer, $blockSize ) or 		# Reading the $blockSize bytes from the file
				die "Error during file reading : $!";

		if ( $bytes lt $blockSize ) {
			print "Read from file: $bytes / $blockSize bytes";
		}

		push @file, $buffer;
	}

	return @file;
}