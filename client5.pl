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
use Time::HiRes qw( gettimeofday tv_interval usleep );

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
#------------------------------------------------------------------------------------------------------------------------------------
#	Creating a UDP socket for file parts transmission to the specified host
$udpSocket = IO::Socket::INET->new (
		PeerAddr 	=> $hostAddr,
		PeerPort 	=> $udpPort,
		Proto 		=> 'udp',
		Type		=> SOCK_DGRAM
	) or die "Couldn't create UDP socket!!!: $!";
#------------------------------------------------------------------------------------------------------------------------------------
my @file = readFile ( $filePath );
# $partsCount = ceil ( $fileSize / $blockSize );
$number = 0;											# Initialization of the counter for transmitions' number
$totalTime = 0;
$totalPackets = 0;
$totalBytes = 0;
$lossCount = 0;
my $startTime = [gettimeofday];
#------------------------------------------------------------------------------------------------------------------------------------
#	1)	---	Sending a file info 
my $message = join ($delim, ( 'INFO', $fileName, $fileSize, $blockSize, md5_hex( join ('', @file) ), $partsCount ));
sendWithACK ( $message, 2 );
#------------------------------------------------------------------------------------------------------------------------------------
my $timeInfo = tv_interval ( $startTime );
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
my $progressBar = Term::ProgressBar->new ( $partsCount ); 	# Initialization of a progress bar with the size of the file
for ( my $c = 0; $c < $partsCount; $c++ ) 
{
	my $data = $file[ $c ];
	my $bytes = $udpSocket->send (join ( $delim, ('DATA', ($c + 1), encode_base64 ( $data ), md5_hex ( $data ), scalar (@file)) ) ) or
				die "Error while send : $!";

	$progressBar->update ( $c + 1 );
	$totalBytes += $bytes;
	$totalPackets ++;
}
#------------------------------------------------------------------------------------------------------------------------------------

#------------------------------------------------------------------------------------------------------------------------------------
#	2.2) -- Checking and repeating							#	
my $ack = 'KO';	
my $t = [gettimeofday];										#
while ( $ack ne 'OK' )										#
{		
	my $tt = [ gettimeofday ];													#
	$udpSocket->send ('CHECK');	
															# Sending 'CHECK' command untill all pieces of file will be received by server
															#
	if ( checkIncomingUDP ( 0.1 ) > 0 ) {						#
	 	$udpSocket->recv ( $buffer, 16000 );					#
	 														#
		print "$ss> CheckIncomingUDP started";	#	
		my @msg = split $delim, $buffer;					#
		$ack = shift @msg;									#
	 														#
	 	if ( $ack eq 'ARQ' ) {	
	 		print "$ack received";							#
			@arq = split (':', shift ( @msg ));			#
		}													#
															#		
		if ( @arq ) {										#
			print "ARQ count: ". scalar @arq;				#
			foreach my $n ( @arq ) {						#
				repeatPart ( $n );
				$lossCount ++;
			}												#
			# usleep ( 10000 );								#
		}													#
	}
	else {
		print "Timeout: ". tv_interval ($tt);
	}
	# if ( checkIncomingUDP ( 3 ) > 0 ) {
	# 	print "Second check is good, time: ". tv_interval ($t). " seconds";
	# }
	undef @arq;												#
}															#
#------------------------------------------------------------------------------------------------------------------------------------
# FINISHING
#------------------------------------------------------------------------------------------------------------------------------------
$totalTime = tv_interval ( $startTime );
sendWithACK ( join $delim, ('FINISH', $totalTime, md5_hex( join ( '', @file )), $totalBytes, $totalPackets) );

print "\n--> $fileSize bytes of file are transfered!";
print "Total: $totalBytes bytes in $totalPackets packets. During ". tv_interval ( $startTime ). " seconds";
print "ARQ count: $lossCount, losses - ". ($lossCount/$totalPackets*100). "%"; 
print "MD5(array): ". md5_hex ( join ( '', @file ) );

#------------------------------------------------------------------------------------------------------------------------------------
#------------------------------------------------------------------------------------------------------------------------------------
sub sendWithACK {
	my $data = shift;
	my $timeout = shift or 1.5;
	my $ack = 'KO';
	
	while ( $ack ne 'OK' ) {
		$udpSocket->send ( $data );
		if ( checkIncomingUDP ($timeout) > 0 ) {
			$udpSocket->recv ( $ack, 5000 );
		}
	}

	return $ack;
}

sub repeatPart {
	my $num = shift;
	$lossCount ++;

	$udpSocket->send (join ( $delim, ('REPEAT', $num, encode_base64 ( $file[ $num-1 ] ), md5_hex ( $file[ $num-1 ] )) ) ) or
				die "Error while send : $!";

	return $res;
}

sub checkIncomingUDP {
	my $timeout = shift or 1.8;
	my $poll = IO::Poll->new ();
	$poll->mask ( $udpSocket => POLLIN );

	return $poll->poll ($timeout);
}

sub readFile {
	my $fname = shift or $filePath;
	my $readSize = 0;
	my $counter = 0;
	open $fh, "<", $filePath;

	while ( not eof ($fh) ) {
		my $bytes = read ( $fh, $buffer, $blockSize ) or 		# Reading the $blockSize bytes from the file
				die "Error during file reading : $!";
		$readSize += $bytes;
		if ( $bytes lt $blockSize ) {
			print "Read from file: $bytes / $blockSize bytes";g
		}
		$file[ $counter ] = $buffer;
		$counter ++;
		# push @file, $buffer;
	}
	$partsCount = scalar @file;
	print "File '$fileName' is in memory - $readSize bytes - $partsCount pieces";
	print "Counter: $counter";

	return @file;
}