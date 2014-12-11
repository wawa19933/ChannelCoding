#!/usr/bin/perl
use strict;
use warnings;

use IO::Socket::INET;
use MIME::Base64;
# use Digest::CRC qw( crc64 crc32 crc ); # Module for CRC calculation
use v5.14;

$| = 1;							# Flushing to SOCKET after each write
$\ = "\n";						# Added as an invisible last element to the parameters passed to the print() function. *doc
my $ask = shift || 0;
my $port = '8849';
my ( $buffer, $message, $counter, $peerAddress, $peerName, $fileSize, $fileName, %fileParts, @arq );

my $socket = IO::Socket::INET->new(
				LocalPort => $port,
				Proto => 'udp',
				Type => SOCK_DGRAM
	) or die "Could not start server!!! : $!";

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () {
	my ( $senderIP, $senderName ) = getIP ($socket->recv ( $message, 2048 )); # Waits untill the packet is received and read socket's buffer to $message
	print length ( $message ) . " bytes from $senderName ($senderIP)";
	
	my @packet = split ';', $message;			# Splitting the packet into array: ( command, numberOfPacket, Data )
	my $cmd = shift @packet;					# Taking command field from packet
	
	 given ($cmd) {
		when ('NAME') {
			# $fileSize = pop @packet;
			# $fileName = pop @packet;
			# open FILE, '>', $fileName || die "Can not open file $fileName for writting: $!";
			openFile ( @packet );
			print "Receiving $fileName ...";
		}
		when ('DATA') {
			receiveData ( @packet );
		}
		when ('CHECK') {
			print scalar @arq;
			prepareARQ ();
			processARQ ();
		}
		when ('FINISH') {
			$counter = 0;
		}
		when ('EXIT') {
			exit;
		}
	 }
}

close $socket;			# Closing the socket
close FILE;				# Closing the file

# ============= Functions ===================
sub receiveData {
	my ( $num, $encoded ) = @_; 				# Packet number and encoded data from socket as parameters
	my $rawData;
	$counter ++;
	
	$rawData = decode_base64 ( $encoded );			# Decoding file part from Base64
}

sub openFile {
	$fileSize = pop @_;
	$fileName = pop @_;
	if ( $ask ) {
		$_ = "";
		print "Enter the file name to save: ";
		$fileName = <>;	
	}
	open FILE, '>', $fileName || die "Can not write the file $fileName: $!";
}

sub prepareARQ {
	my $count = 0;
	my $packetsCount = $fileSize / 1024;
	for ( my $i = 0; $i < $packetsCount; $i++ ) {
		my $ok = 0;
		foreach my $k ( keys %fileParts ) {
			if ( $i == $k ) {
				$ok = 1;
				break;
			}
		}
		if ( $ok ) {
			continue;
		}
		else {
			push @arq, $i;
		}
	}
}

sub processARQ {
	my $count = @arq;
	foreach my $num ( @arq ) {
		my @msg = ( 'ARQ', $num, $count-- );
		$socket->send ( join ';', @msg );
	}
}

sub getIP {
	my ( $port, $iaddr ) = sockaddr_in ( shift @_ );
	my $peerAddress = inet_ntoa( $iaddr );
	my $peerName = gethostbyaddr ( $iaddr, AF_INET );
	
	if ( wantarray() ) {				# List context
		return ( $peerAddress, $peerName );
	} 
	elsif ( defined wantarray() ) {		# Scalar context
		return $peerAddress;
	} 
}