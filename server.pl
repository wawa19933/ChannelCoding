#!/usr/bin/perl
use strict;
use warnings;

use IO::Socket::INET;
use MIME::Base64;
use v5.14;

$| = 1;							# Flushing to SOCKET after each write
$\ = "\n";						# Added as an invisible last element to the parameters 
								# passed to the print() function. *doc
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
		when ('FINISH') {
			$counter = 0;
		}
		when ('EXIT') {
			exit;
		}
	 }
}

close $socket;

# ============= Functions ===================
sub receiveData {
	my ( $num, $encoded, $hash ) = @_; 				# Packet number and encoded data from socket as parameters
	my ( $rawData, $crc );
	$counter ++;
	
	# if ( $counter != $num ) {
		# @arq = $counter;
	# } 
	
	$rawData = decode_base64 ( $encoded );
	$crc = crc32 ( $rawData );
	if ( $crc == $hash ) {
		$fileParts{ $num } = $rawData;
	}
	else {
		print "$num - Checksums differ!"
		push @arq, $num;
	}
}

sub openFile {
	my $fileSize = pop @_;
	my $fileName = pop @_;
	if ( $ask ) {
		$_ = "";
		print "Enter the file name to save: ";
		$fileName = <>;	
	}
	open FILE, '>', $fileName || die "Can not write the file $fileName: $!";
}

sub checkBuffer {
	foreach $k ( keys %fileParts ) {
		
	}
}

sub getIP {
	my ( $port, $iaddr ) = sockaddr_in ( shift @_ );
	my $peerAddress = inet_ntoa( $iaddr );
	my $peerName = gethostbyaddr ( $iaddr, AF_INET );
	
	# print "$peerAddress, $peerName";
	if ( wantarray() ) {				# List context
		return ( $peerAddress, $peerName );
	} 
	elsif ( defined wantarray() ) {		# Scalar context
		return $peerAddress;
	} 
	else {								# Void context
		return;
	} 
}