package Shared;

use v5.11;
use Exporter qw(import);
#use Data::Dumper;
our @EXPORT = qw(sync_can_run write_pid);

sub sync_can_run {
    my $dbh = shift;
    my $sth = $dbh->prepare('Select count(*) as aantal From teamcreated');
    $sth->execute();
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    if ($row->{'aantal'} eq 0){ 
        return 1;
    }else{ 
        return 0;
    }
}

sub write_pid {
    my $pidFile = shift;
    if (open (FH, '>', $pidFile)){
        print FH $$."\n";
        close FH;
        return 1;
    }else{
        warn "Fout bij het openen van $pidFile: ".$!;
        return 0;
    }
}

42;