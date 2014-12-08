#!/usr/bin/perl

use strict;
use warnings;

use IO::Socket::INET;
use MIME::Base64;
use v5.14;

$| = 1;							# Flushing to SOCKET after each write
$\ = "\n";						# Added as an invisible last element to the parameters 
								# passed to the print() function. *doc
# my $endl = "\n";
my $ask = shift or 0;
my $port = '8849';
my ( $data, $message, $counter, $peerAddress, $peerName );

my $socket = IO::Socket::INET->new(
				LocalPort => $port,
				Proto => 'udp',
				Type => SOCK_DGRAM
) or die "Could not start server!!! : $!\n";

##		Starting the receiving loop that is controlled by 	##
##		commands from the client via Switch-like statment	##
while () {
	my ( $senderIP, $senderName ) = getIP $socket->recv ( $message, 2048 );		# Waits untill the packet is received and read socket's buffer to $message
	print length ( $message ) . " bytes from $senderName ($senderIP)";
	
	my @parts = split ';', $message;		# Splitting the packet into array: ( command, numberOfPacket, Data )
	my $cmd = shift @parts;
	
	 given ($cmd) {
		when ('NAME') {
			
			print $data . $endl;
			
		}
		when ('DATA') {
			print decode_base64( $data ) . $endl . $endl;
		}
		
		when ('EXIT') {
			exit;
		}
	 }
}

close $socket;

# ============= Functions ===================
sub receiveData {
	my ( $num, $encoded ) = @_; 			# Packet number and encoded data from socket as parameters
	my ( $rawData, $ecncoded, $output );
	$counter ++;
	
	if ( $counter != $num ) {
		
	} 
	
	
}

sub openFile {
	my $fileName = shift;
	if ( $ask ) {
		$_ = "";
		print "Enter the file name to save: ";
		$fileName = <>;	
	}
	open FILE, '>', $fileName or die "Can not write the file $fileName: $!";
}

sub getIP {
	my ( $port, $iaddr ) = sockaddr_in ( shift );
	
	my $peerAddress = inet_ntoa( $iaddr );
	my $peerName = gethostbyaddr ( $iaddr, AF_INET );
	
	if ( wantarray() ) {				# List context
		return [ $peerAddress, $peerHost ];
	} 
	elsif ( defined wantarray() ) {		# Scalar context
		return $peerAddress;
	} 
	else {								# Void context
		return;
	} 
}