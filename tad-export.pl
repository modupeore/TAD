#!/usr/bin/env perl
use warnings;
use strict;
use Pod::Usage;
use Getopt::Long;
use File::Spec;
use File::Basename;
use Cwd qw(abs_path);
use lib dirname(abs_path $0) . '/lib';
use threads;
use Thread::Queue;
use CC::Create;
use CC::Parse;

our $VERSION = '$ Version: 1 $';
our $DATE = '$ Date: 2016-11-28 15:14:00 (Thu, 28 Nov 2016) $';
our $AUTHOR= '$ Author:Modupe Adetunji <amodupe@udel.edu> $';

#--------------------------------------------------------------------------------

our ($verbose, $efile, $help, $man, $nosql, $tmpout);
our ($dbh, $sth, $found, $count, @header, $connect, $fastbit);
my ($query, $output,$avgfpkm, $gene, $tissue, $organism, $genexp, $chrvar, $sample, $chromosome, $varanno, $region, $vcf);
my $dbdata;
my ($table, $outfile, $syntax, $status);
my $tmpname = rand(20);
our (%ARRAYQUERY, %SAMPLE);

#genexp module
my (@genearray, @VAR, $newfile, @threads, @headers); #splicing the genes into threads
my ($realstart, $realstop, $queue);
my (%FPKM, %CHROM, %POSITION, %REALPOST);
#chrvar module
my (%VARIANTS, %SNPS, %INDELS);
#vcf optino
my (%GT, %TISSUE, %REF, %ALT, %QUAL, %CSQ, %DBSNP, $chrheader);
my (%ODACSQ,%number, %NEWQUAL, %NEWCSQ, %NEWREF, %NEWDBSNP, %NEWALT,%NEWGT);
my (%subref, %subalt, %subgt,%MTD);

#--------------------------------------------------------------------------------

sub printerr; #declare error routine
our $default = DEFAULTS(); #default error contact
processArguments(); #Process input

my %all_details = %{connection($connect, $default)}; #get connection details
if ($query) { #if user query mode selected
	$query =~ s/^\s+|\s+$//g;
	$verbose and printerr "NOTICE:\t User query module selected\n";
	undef %ARRAYQUERY;
	$dbh = mysql($all_details{'MySQL-databasename'}, $all_details{'MySQL-username'}, $all_details{'MySQL-password'}); #connect to mysql
  $sth = $dbh->prepare($query); $sth->execute();

	$table = Text::TabularDisplay->new( @{ $sth->{NAME_uc} } );#header
  @header = @{ $sth->{NAME_uc} };
	$count = 0;
	while (my @row = $sth->fetchrow_array()) {
		$count++; $table->add(@row); $ARRAYQUERY{$count} = [@row];
	}	
	unless ($count == 0){
		if ($output) { #if output file is specified, else, result will be printed to the screen
			$outfile = @{ open_unique($output) }[1];
			open (OUT, ">$outfile") or die "ERROR:\t Output file $output can be not be created\n";
			print OUT join("\t", @header),"\n";
			foreach my $row (sort {$a <=> $b} keys %ARRAYQUERY) {
				no warnings 'uninitialized';
				print OUT join("\t", @{$ARRAYQUERY{$row}}),"\n";
			} close OUT;
		} else {
			printerr $table-> render, "\n"; #print display
		}
		$verbose and printerr "NOTICE:\t Summary: $count rows in result\n";
	} else { printerr "NOTICE:\t No Results based on search criteria: '$query' \n"; }
} #end of user query module

if ($dbdata){ #if db 2 data mode selected
	if ($avgfpkm){ #looking at average fpkms
		$count = 0;
		undef %ARRAYQUERY;
		#making sure required attributes are specified.
		$verbose and printerr "TASK:\t Average Fpkm Values of Individual Genes\n";
		unless ($gene && $organism){
			unless ($gene) {printerr "ERROR:\t Gene option '-gene' is not specified\n"; }
			unless ($organism) {printerr "ERROR:\t Organism option '-species' is not specified\n"; }
			pod2usage("ERROR:\t Details for -avgfpkm are missing. Review 'tad-interact.pl -d' for more information");
		}
		$dbh = mysql($all_details{'MySQL-databasename'}, $all_details{'MySQL-username'}, $all_details{'MySQL-password'}); #connect to mysql
		#checking if the organism is in the database
		$organism =~ s/^\s+|\s+$//g;
		$sth = $dbh->prepare("select organism from Animal where organism = '$organism'");$sth->execute(); $found =$sth->fetch();
		unless ($found) { pod2usage("ERROR:\t Organism name '$organism' is not found in database. Consult 'tad-interact.pl -d' for more information"); }
		$verbose and printerr "NOTICE:\t Organism selected: $organism\n";
		
		if ($tissue) {
			my @tissue = split(",", $tissue); undef $tissue; 
			foreach (@tissue) {
				$_ =~ s/^\s+|\s+$//g;
				$sth = $dbh->prepare("select distinct tissue from Sample where tissue = '$_'");$sth->execute(); $found =$sth->fetch();
				unless ($found) { pod2usage("ERROR:\t Tissue name '$_' is not found in database. Consult 'tad-interact.pl -d' for more information"); }
				$tissue .= $_ .",";
			}chop $tissue;
			$verbose and printerr "NOTICE:\t Tissue(s) selected: $tissue\n";
		} else {
			$verbose and printerr "NOTICE:\t Tissue(s) selected: 'all tissue for $organism'\n";
			$sth = $dbh->prepare("select tissue from vw_sampleinfo where organism = '$organism' and genes is not null"); #get samples
			$sth->execute or die "SQL Error: $DBI::errstr\n";
			my $tnumber= 0;
			while (my $row = $sth->fetchrow_array() ) {
				$tnumber++;
				$SAMPLE{$tnumber} = $row;
				$tissue .= $row.",";
			} chop $tissue;
		} #checking sample options
		my @tissue = split(",", $tissue);
		$verbose and printerr "NOTICE:\t Gene(s) selected: $gene\n";
		my @genes = split(",", $gene);
		foreach my $fgene (@genes){
			$fgene =~ s/^\s+|\s+$//g;
			foreach my $ftissue (@tissue) {
				$syntax = "call usp_gdtissue(\"".$fgene."\",\"".$ftissue."\",\"". $organism."\")";
				$sth = $dbh->prepare($syntax);
				$sth->execute or die "SQL Error: $DBI::errstr\n";
				@header = @{ $sth->{NAME_uc} }; #header
				splice @header, 1, 0, 'TISSUE';
				$table = Text::TabularDisplay->new( @header );
				my $found = $sth->fetch();
				if ($found) {	
					while (my ($genename, $max, $avg, $min) = $sth->fetchrow_array() ) { #content
						push my @row, ($genename, $ftissue, $max, $avg, $min);
						$count++;
						$ARRAYQUERY{$genename}{$ftissue} = [@row];
					}
				} else {
					printerr "NOTICE:\t No Results found with gene '$fgene'\n";
				}
			}
		}
		unless ($count == 0) {
			if ($output) { #if output file is specified, else, result will be printed to the screen
				$outfile = @{ open_unique($output) }[1];
				open (OUT, ">$outfile") or die "ERROR:\t Output file $output can be not be created\n";
				print OUT join("\t", @header),"\n";
				foreach my $a (sort keys %ARRAYQUERY){
					foreach my $b (sort keys % { $ARRAYQUERY{$a} }){
						print OUT join("\t", @{$ARRAYQUERY{$a}{$b}}),"\n";
					}
				} close OUT;
			} else {
				foreach my $a (sort keys %ARRAYQUERY){
					foreach my $b (sort keys % { $ARRAYQUERY{$a} }){
						$table->add(@{$ARRAYQUERY{$a}{$b}});
					}
				} 
				printerr $table-> render, "\n"; #print display
			}	
			$verbose and printerr "NOTICE:\t Summary: $count rows in result\n";
		} else { printerr "\nNOTICE:\t No Results based on search criteria: '$gene' \n"; }
	} #end of avgfpkm module
	
	if ($genexp){ #looking at gene expression per sample
		`mkdir -p tadtmp/`;
		$count = 0;
		#making sure required attributes are specified.
		$verbose and printerr "TASK:\t Gene Expression (FPKM) information across Samples\n";
		unless ($organism){
			printerr "ERROR:\t Organism option '-species' is not specified\n";
			pod2usage("ERROR:\t Details for -genexp are missing. Review 'tad-interact.pl -e' for more information");
		}
		$dbh = mysql($all_details{'MySQL-databasename'}, $all_details{'MySQL-username'}, $all_details{'MySQL-password'}); #connect to mysql
		#checking if the organism is in the database
		$organism =~ s/^\s+|\s+$//g;
		$sth = $dbh->prepare("select organism from Animal where organism = '$organism'");$sth->execute(); $found =$sth->fetch();
		unless ($found) { pod2usage("ERROR:\t Organism name '$organism' is not found in database. Consult 'tad-interact.pl -e' for more information"); }
		$verbose and printerr "NOTICE:\t Organism selected: $organism\n";
		#checking if sample is in the database
		if ($sample) {
			my @sample = split(",", $sample); undef $sample; 
			foreach (@sample) {
				$_ =~ s/^\s+|\s+$//g;
				$sth = $dbh->prepare("select distinct sampleid from Sample where sampleid = '$_'");$sth->execute(); $found =$sth->fetch();
				unless ($found) { pod2usage("ERROR:\t Sample ID '$_' is not in the database. Consult 'tad-interact.pl -e' for more information"); }
				$sample .= $_ .",";
			}chop $sample;
			$verbose and printerr "NOTICE:\t Sample(s) selected: $sample\n";
		} else {
			$verbose and printerr "NOTICE:\t Sample(s) selected: 'all samples for $organism'\n";
			$sth = $dbh->prepare("select sampleid from vw_sampleinfo where organism = '$organism' and genes is not null"); #get samples
			$sth->execute or die "SQL Error: $DBI::errstr\n";
			my $snumber= 0;
			while (my $row = $sth->fetchrow_array() ) {
				$snumber++;
				$SAMPLE{$snumber} = $row;
				$sample .= $row.",";
			} chop $sample;
		} #checking sample options
		@headers = split(",", $sample);
		$syntax = "select geneshortname, fpkm, sampleid, chromnumber, chromstart, chromstop from GenesFpkm where";
		if ($gene) {
			$syntax .= " (";
			my @genes = split(",", $gene); undef $gene;
			foreach (@genes){
				$_ =~ s/^\s+|\s+$//g;
				$syntax .= " geneshortname like '%$_%' or";
				$gene .= $_.",";
			} chop $gene;
			$verbose and printerr "NOTICE:\t Gene(s) selected: '$gene'\n";
			$syntax = substr($syntax, 0, -2); $syntax .= " ) and";
		} else {
			$verbose and printerr "NOTICE:\t Gene(s) selected: 'all genes'\n";
		}
		printerr "NOTICE:\t Processing Gene Expression for each library .";
		foreach (@headers){ 
			printerr ".";
			my $newsyntax = $syntax." sampleid = '$_' ORDER BY geneid desc;";
			$sth = $dbh->prepare($newsyntax);
			$sth->execute or die "SQL Error:$DBI::errstr\n";
			while (my ($gene_id, $fpkm, $library_id, $chrom, $start, $stop) = $sth->fetchrow_array() ) {
				$FPKM{"$gene_id|$chrom"}{$library_id} = $fpkm;
				$CHROM{"$gene_id|$chrom"} = $chrom;
				$POSITION{"$gene_id|$chrom"}{$library_id} = "$start|$stop";
			}
		} #end foreach extracting information from th database	
		printerr " Done\n";
		printerr "NOTICE:\t Processing Results ...";
		foreach my $newgene (sort keys %CHROM){ #turning the genes into an array
			if ($newgene =~ /^[\d\w]/){ push @genearray, $newgene;}
		}
		push @VAR, [ splice @genearray, 0, 2000 ] while @genearray; #sub array the genes into a list of 2000
	
		foreach (0..$#VAR){ $newfile .= "tadtmp/tmp_".$tmpname."-".$_.".zzz "; } #foreach sub array create a temporary file
		$queue = new Thread::Queue();
		my $builder=threads->create(\&main); #create thread for each subarray into a thread
		push @threads, threads->create(\&processor) for 1..5; #execute 5 threads
		$builder->join; #join threads
		foreach (@threads){$_->join;}
		my $command="cat $newfile >> $tmpout"; #path into temporary output
		system($command);
		`rm -rf tadtmp/`; #remove all temporary files
		printerr " Done\n";
		@header = qw|GENE CHROM|; push @header, @headers;
		$count = `cat $tmpout | wc -l`; chomp $count;
		open my $content,"<",$tmpout; `rm -rf $tmpout`;
		$table = Text::TabularDisplay->new( @header );
		unless ($count == 0) {
			if ($output){
				$outfile = @{ open_unique($output) }[1];
				open (OUT, ">$outfile") or die "ERROR:\t Output file $output can be not be created\n";
				print OUT join("\t", @header),"\n";
				print OUT <$content>;
				close OUT;
			} else {
				while (<$content>){ chomp;$table->add(split "\t"); }
				printerr $table-> render, "\n"; #print display
			}
			$verbose and printerr "NOTICE:\t Summary: $count rows in result\n";
		} else { printerr "\nNOTICE:\t No Results based on search criteria \n"; }
	} #end of genexp module
	
	if ($chrvar){ #looking at chromosomal variant distribution
		undef %SAMPLE; undef %ARRAYQUERY;
		$count = 0;
		#making sure required attributes are specified.
		$verbose and printerr "TASK:\t Chromosomal Variant Distribution Across Samples\n";
		unless ($organism){
			printerr "ERROR:\t Organism option '-species' is not specified\n";
			pod2usage("ERROR:\t Details for -chrvar are missing. Review 'tad-interact.pl -f' for more information");
		}
		$dbh = mysql($all_details{'MySQL-databasename'}, $all_details{'MySQL-username'}, $all_details{'MySQL-password'}); #connect to mysql
		#checking if the organism is in the database
		$organism =~ s/^\s+|\s+$//g;
		$sth = $dbh->prepare("select organism from Animal where organism = '$organism'");$sth->execute(); $found =$sth->fetch();
		unless ($found) { pod2usage("ERROR:\t Organism name '$organism' is not found in database. Consult 'tad-interact.pl -f' for more information"); }
		$verbose and printerr "NOTICE:\t Organism selected: $organism\n";
		#checking if sample is in the database
		if ($sample) {
			my @sample = split(",", $sample); undef $sample; 
			foreach (@sample) {
				$_ =~ s/^\s+|\s+$//g;
				$sth = $dbh->prepare("select distinct sampleid from Sample where sampleid = '$_'");$sth->execute(); $found =$sth->fetch();
				unless ($found) { pod2usage("ERROR:\t Sample ID '$_' is not in the database. Consult 'tad-interact.pl -f' for more information"); }
				$sample .= $_ .",";
			} chop $sample;
			$verbose and printerr "NOTICE:\t Sample(s) selected: $sample\n";
		} else {
			$verbose and printerr "NOTICE:\t Sample(s) selected: 'all samples for $organism'\n";
			$sth = $dbh->prepare("select sampleid from vw_sampleinfo where organism = '$organism' and totalvariants is not null"); #get samples
			$sth->execute or die "SQL Error: $DBI::errstr\n";
			my $snumber= 0;
			while (my $row = $sth->fetchrow_array() ) {
				$snumber++;
				$SAMPLE{$snumber} = $row;
				$sample .= $row.",";
			} chop $sample;
		} #checking sample options
		@headers = split(",", $sample);
		$syntax = "select sampleid, chrom, count(*) from VarResult where sampleid in ( ";
		foreach (@headers) { $syntax .= "'$_',"; } chop $syntax; $syntax .= ")";			
		if ($chromosome) {
			my @chromosome = split(",", $chromosome); undef $chromosome;
			$syntax .= " and (";
			foreach (@chromosome) {
				$_ =~ s/^\s+|\s+$//g;
				$sth = $dbh->prepare("select distinct chrom from VarResult where chrom = '$_'");$sth->execute(); $found =$sth->fetch();
				unless ($found) { pod2usage("ERROR:\t Chromosome '$_' is not in the database. Consult 'tad-interact.pl -f' for more information"); }
				$syntax .= "chrom = '$_' or ";
				$chromosome .= $_ .",";
			} $syntax = substr($syntax,0, -3); $syntax .= ") "; chop $chromosome;
			$verbose and printerr "NOTICE:\t Chromosome(s) selected: $chromosome\n";
		} else {
			$verbose and printerr "NOTICE:\t Chromosome(s) selected: 'all chromosomes'\n";
		}
		my $endsyntax = "group by sampleid, chrom order by sampleid, length(chrom),chrom";
		my $allsyntax = $syntax.$endsyntax; 
		$sth = $dbh->prepare($allsyntax); 
		$sth->execute or die "SQL Error:$DBI::errstr\n";
		my $number = 0;
		while (my ($sampleid, $chrom, $counted) = $sth->fetchrow_array() ) {
			$number++;
			$CHROM{$sampleid}{$number} = $chrom;
			$VARIANTS{$sampleid}{$chrom} = $counted;
		}	
		$allsyntax = $syntax."and variantclass = 'SNV' ".$endsyntax; #counting SNPS
		$sth = $dbh->prepare($allsyntax); 
		$sth->execute or die "SQL Error:$DBI::errstr\n";
		while (my ($sampleid, $chrom, $counted) = $sth->fetchrow_array() ) {
			$SNPS{$sampleid}{$chrom} = $counted;
		}
		$allsyntax = $syntax."and (variantclass = 'insertion' or variantclass = 'deletion') ".$endsyntax; #counting INDELs
		$sth = $dbh->prepare($allsyntax); 
		$sth->execute or die "SQL Error:$DBI::errstr\n";
		while (my ($sampleid, $chrom, $counted) = $sth->fetchrow_array() ) {
			$INDELS{$sampleid}{$chrom} = $counted;
		}
		@header = qw(SAMPLE CHROMOSOME VARIANTS SNPs INDELs);
		$table = Text::TabularDisplay->new(@header);
		my @content;
		foreach my $ids (sort keys %VARIANTS){  
			if ($ids =~ /^[0-9a-zA-Z]/) {
				foreach my $no (sort {$a <=> $b} keys %{$CHROM{$ids} }) {
					$count++;
					my @row = ();
					push @row, ($ids, $CHROM{$ids}{$no}, $VARIANTS{$ids}{$CHROM{$ids}{$no}});
					if (exists $SNPS{$ids}{$CHROM{$ids}{$no}}){
						push @row, $SNPS{$ids}{$CHROM{$ids}{$no}};
					} else {
						push @row, "0";
					}
					if (exists $INDELS{$ids}{$CHROM{$ids}{$no}}){
						push @row, $INDELS{$ids}{$CHROM{$ids}{$no}};
					}
					else {
						push @row, "0";
					}
					$table->add(@row);
					$ARRAYQUERY{$count} = [@row];
				}
			}
		}
		unless ($count == 0) {
			if ($output){
				$outfile = @{ open_unique($output) }[1];
				open (OUT, ">$outfile") or die "ERROR:\t Output file $output can be not be created\n";
				print OUT join("\t", @header),"\n";
				foreach (sort keys %ARRAYQUERY) { print OUT join("\t",@{$ARRAYQUERY{$_}}), "\n"; }
				close OUT;
			} else {
				printerr $table-> render, "\n"; #print display
			}
			$verbose and printerr "NOTICE:\t Summary: $count rows in result\n";
		} else { printerr "\nNOTICE:\t No Results based on search criteria \n"; }
	} #end of chrvar module
	
	if ($varanno){ #looking at variants 
		undef %SAMPLE; undef %ARRAYQUERY; undef $status;
		$count = 0;
		#making sure required attributes are specified.
		$verbose and printerr "TASK:\t Associated Variant Annotation Information\n";
		unless ($organism){
			printerr "ERROR:\t Organism option '-species' is not specified\n";
			pod2usage("ERROR:\t Details for -varanno are missing. Review 'tad-interact.pl' for more information");
		}
		if ($gene) { $verbose and printerr "SUBTASK: Gene-associated Variants with Annotation Information\n"; }
		if ($chromosome) { $verbose and printerr "SUBTASK: Chromosomal region-associated Variants with Annotation Information\n"; }
		$dbh = mysql($all_details{'MySQL-databasename'}, $all_details{'MySQL-username'}, $all_details{'MySQL-password'}); #connect to mysql
		$fastbit = fastbit($all_details{'FastBit-path'}, $all_details{'FastBit-foldername'});  #connect to fastbit
		$organism =~ s/^\s+|\s+$//g;
		$sth = $dbh->prepare("select organism from Animal where organism = '$organism'");$sth->execute(); $found =$sth->fetch();
		unless ($found) { pod2usage("ERROR:\t Organism name '$organism' is not found in database. Consult 'tad-interact.pl -f' for more information"); }
		$verbose and printerr "NOTICE:\t Organism selected: $organism\n";
		my $number = 0;
		$syntax = "ibis -d $fastbit -q \"select chrom,position,refallele,altallele,variantclass,consequence,group_concat(genename),group_concat(dbsnpvariant), group_concat(sampleid) where organism='$organism'";
		my $vcfsyntax = "ibis -d $fastbit -q \"select sampleid, chrom, position, refallele, altallele, quality, consequence, proteinposition, genename, geneid, feature, transcript, genetype, aachange,  codonchange, dbsnpvariant, variantclass, zygosity, tissue where organism='$organism'";
	
		unless ($gene) {
			if ($chromosome){
				my @chromosomes = split(",", $chromosome); undef $chromosome;
				foreach (@chromosomes){ $_ =~ s/^\s+|\s+$//g; $chromosome .= $_.","; } chop $chromosome;
				$verbose and printerr "NOTICE:\t Chromosome(s) selected: '$chromosome'\n";
				$chrheader = $chromosome;
				$syntax .= " and (";
				$vcfsyntax .= " and (";
				foreach (@chromosomes) {
					$syntax .= "chrom = '$_' or ";
					$vcfsyntax .= "chrom = '$_' or ";
				}
				$syntax = substr($syntax, 0, -3); $syntax .= ") ";
				$vcfsyntax = substr($vcfsyntax, 0, -3); $vcfsyntax .= ") ";
				if ($region){
					if ($region =~ /\-/) {
						my @region = split("-", $region);
						$syntax .= "and position between $region[0] and $region[1] ";
						$vcfsyntax .= "and position between $region[0] and $region[1] ";
						$chrheader .= ":$region[0]\-$region[1]";
						$verbose and printerr "NOTICE:\t Region: between $region[0] and $region[1]\n";
					} else {
						my $start = $region-1500;
						my $stop = $region+1500;
						$syntax .= "and position between ". $start." and ". $stop;
						$vcfsyntax .= "and position between ". $start." and ". $stop;
						$chrheader .= ":$start\-$stop";
						$verbose and printerr "NOTICE:\t Region: 3000bp region of $region\n";
					}
				} #end if region
			} #end if chromosome
			else { $verbose and printerr "NOTICE:\t Chromosome(s) selected: 'all chromosomes'\n"; $chrheader="all chromosomes";}
			$syntax .= "\" -o $nosql";
			$vcfsyntax .= "\" -o $nosql";
			if ($vcf) {
				`$vcfsyntax 2>> $efile`;
				open(IN,'<',$nosql); my @nosqlcontent = <IN>; close IN; `rm -rf $nosql`;
				foreach (@nosqlcontent) {
					chomp; $count++;
					my @arraynosqlA = split (",",$_,9); foreach (@arraynosqlA[0..7]) { $_ =~ s/"//g; $_ =~ s/^\s+|\s+$//g;}
					my @arraynosqlB = split("\", \"", $arraynosqlA[8]); foreach (@arraynosqlB) { $_ =~ s/"//g ; $_ =~ s/^\s+|\s+$//g; $_ =~ s/NULL//g;}
					push my @row, (@arraynosqlA[0..6], @arraynosqlB[0..4], $arraynosqlA[7], @arraynosqlB[5..$#arraynosqlB]);
					PROCESS(@row);
				}
			} else {
				`$syntax 2>> $efile`;
				open(IN,'<',$nosql); my @nosqlcontent = <IN>; close IN; `rm -rf $nosql`;
				foreach (@nosqlcontent) {
					chomp; $count++;
					my @arraynosqlA = split (",",$_,3); foreach (@arraynosqlA[0..1]) { $_ =~ s/"//g;}
					my @arraynosqlB = split("\", \"", $arraynosqlA[2]); foreach (@arraynosqlB) { $_ =~ s/"//g ; $_ =~ s/NULL/-/g;}
					my @arraynosqlC = uniq(sort(split(", ", $arraynosqlB[4]))); if ($#arraynosqlC > 0 && $arraynosqlC[0] =~ /^-/){ shift @arraynosqlC; }
					my @arraynosqlD = uniq(sort(split(", ", $arraynosqlB[5]))); if ($#arraynosqlD > 0 && $arraynosqlD[0] =~ /^-/){ shift @arraynosqlD; }
					push my @row, @arraynosqlA[0..1], @arraynosqlB[0..3], join(",", @arraynosqlC) , join(",", @arraynosqlD), join (",", uniq(sort(split (", ", $arraynosqlB[6]))));
					$SAMPLE{$arraynosqlA[0]}{$arraynosqlA[1]}{$arraynosqlB[3]} = [@row];
				}
				foreach my $aa (sort {$a cmp $b || $a <=> $b} keys %SAMPLE){
					foreach my $bb (sort {$a cmp $b || $a <=> $b} keys % {$SAMPLE{$aa} }){
						foreach my $cc (sort {$a cmp $b || $a <=> $b} keys % {$SAMPLE{$aa}{$bb} }){
							$number++;
							$ARRAYQUERY{$number} = [@{ $SAMPLE{$aa}{$bb}{$cc} }];
						}
					}
				} #end parsing the results to arrayquery
			}
		} #end unless gene
		else {
			my @genes = split(",", $gene); undef $gene;
			foreach (@genes){ $_ =~ s/^\s+|\s+$//g; $gene .= $_.","; } chop $gene;
			$verbose and printerr "NOTICE:\t Gene(s) selected: '$gene'\n";
			foreach (@genes) {
				my $gsyntax = $syntax." and genename like '%".uc($_)."%'\" -o $nosql";
				`$gsyntax 2>> $efile`;
				open(IN,'<',$nosql); my @nosqlcontent = <IN>; close IN; `rm -rf $nosql`;
				if ($#nosqlcontent < 0) {$status .= "NOTICE:\t No variants are associated with gene '$_' \n";}
				else {
					foreach (@nosqlcontent) {
						chomp; $count++;
						my @arraynosqlA = split (",",$_,3); foreach (@arraynosqlA[0..1]) { $_ =~ s/"//g;}
						my @arraynosqlB = split("\", \"", $arraynosqlA[2]); foreach (@arraynosqlB) { $_ =~ s/"//g ; $_ =~ s/NULL/-/g;}
						push my @row, @arraynosqlA[0..1], @arraynosqlB[0..3], join(",", uniq(sort(split(", ", $arraynosqlB[4])))) , join(",", uniq(sort(split(", ", $arraynosqlB[5])))), join (",", uniq(sort(split (", ", $arraynosqlB[6]))));
						$SAMPLE{$gene}{$arraynosqlA[0]}{$arraynosqlA[1]}{$arraynosqlB[3]} = [@row];
					}
				}
			}
			foreach my $aa (keys %SAMPLE){ #getting content to output
				foreach my $bb (sort {$a cmp $b || $a <=> $b} keys % {$SAMPLE{$aa} }){
					foreach my $cc (sort {$a <=> $b} keys % {$SAMPLE{$aa}{$bb} }) {
						foreach my $dd (sort keys % {$SAMPLE{$aa}{$bb}{$cc} }) {
							$number++;
							$ARRAYQUERY{$number} = [@{ $SAMPLE{$aa}{$bb}{$cc}{$dd} }];
						}
					}
				}
			} #end parsing the results to arrayquery
		} #end if gene
		
		@header = qw(Chrom Position Refallele Altallele Variantclass Consequence Genename Dbsnpvariant Sampleid);
		tr/a-z/A-Z/ for @header;
		$table = Text::TabularDisplay->new(@header); #header
		
		unless ($count == 0) {
			if ($output) { #if output file is specified, else, result will be printed to the screen
				$outfile = @{ open_unique($output) }[1];
				open (OUT, ">$outfile") or die "ERROR:\t Output file $output can be not be created\n";
				unless ($vcf) {
					print OUT join("\t", @header),"\n";
					foreach my $a (sort keys %ARRAYQUERY){
						print OUT join("\t", @{$ARRAYQUERY{$a}}),"\n";
					} 
				} else {
					SORTER();
					MTD();
					#our $headerinfo = HEADER();
					print OUT HEADER($organism, $chrheader); #$headerinfo;
					foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %NEWREF) {
						foreach my $position (sort {$a<=> $b} keys %{$NEWREF{$chrom}}) {
							foreach my $ref (sort {$a cmp $b} keys %{$NEWREF{$chrom}{$position}}) {
								print OUT "chr",$chrom,"\t",$position,"\t",$NEWDBSNP{$chrom}{$position}{$ref},"\t",$NEWREF{$chrom}{$position}{$ref},"\t";
								print OUT $NEWALT{$chrom}{$position}{$ref},"\t",$NEWQUAL{$chrom}{$position}{$ref},"\tPASS\tCSQ=",$NEWCSQ{$chrom}{$position}{$ref};
								print OUT ";MTD=",$MTD{$chrom}{$position}{$ref},"\tGT\t",$NEWGT{$chrom}{$position}{$ref};
								print OUT "\n";
							}
						}
					}	
				} close OUT;
			} else {
				foreach my $a (sort keys %ARRAYQUERY){
					$table->add(@{$ARRAYQUERY{$a}});
				}
				printerr $table-> render, "\n"; #print display
			}	
			$verbose and printerr "NOTICE:\t Summary: $count rows in result\n";
		} else { printerr "\nNOTICE:\t No Results based on search criteria \n"; }
	} #end of varanno module
} #end of db2data module
#output: the end
printerr "-----------------------------------------------------------------\n";
printerr $status;
unless ($count == 0) { if ($output) { printerr "NOTICE:\t Successful export of user report to '$outfile'\n"; } }
printerr ("NOTICE:\t Summary in log file $efile\n");
print LOG "TransAtlasDB Completed:\t", scalar(localtime),"\n";
printerr "-----------------------------------------------------------------\n";
close (LOG);

#--------------------------------------------------------------------------------

sub processArguments {
	my @commandline = @ARGV;
  GetOptions('verbose|v'=>\$verbose, 'help|h'=>\$help, 'man|m'=>\$man, 'query=s'=>\$query, 'db2data'=>\$dbdata, 'o|output'=>\$output,
						 'avgfpkm'=>\$avgfpkm, 'gene=s'=>\$gene, 'tissue=s'=>\$tissue, 'species=s'=>\$organism, 'genexp'=>\$genexp,'vcf'=>\$vcf,
						 'samples|sample=s'=>\$sample, 'chrvar'=>\$chrvar, 'chromosome=s'=>\$chromosome, 'varanno'=>\$varanno,'region=s'=>\$region) or pod2usage ();

  $help and pod2usage (-verbose=>1, -exitval=>1, -output=>\*STDOUT);
  $man and pod2usage (-verbose=>2, -exitval=>1, -output=>\*STDOUT);  
  pod2usage(-msg=>"ERROR:\t Invalid syntax specified, choose -query or -db2data.") unless ( $query || $dbdata);
  pod2usage(-msg=>"ERROR:\t Invalid syntax specified @commandline") if (($query && $dbdata)|| ($avgfpkm && $genexp) || ($gene && $chromosome));
	if ($dbdata) { pod2usage(-msg=>"ERROR:\t Invalid syntax specified @commandline, choose -avgfpkm or -genexp or -chrvar or -varanno") unless ($avgfpkm || $genexp || $chrvar || $varanno); }
	if ($vcf) { pod2usage(-msg=>"ERROR:\t VCF output is not configured for @commandline") unless ($varanno && ! $gene); }
	if ($vcf) { pod2usage("ERROR:\t Syntax error. Specify -output <filename>") unless ($output); }
  @ARGV<=1 or pod2usage("Syntax error");
	if ($output) {
		@ARGV==1 or pod2usage("ERROR:\t Syntax error. Specify the output filename");
		$output = $ARGV[0];
		$output = fileparse($output, qr/\.[^.]*(\..*)?$/).".txt";
		$output = fileparse($output, qr/\.[^.]*(\..*)?$/).".vcf" if ($vcf);
	}
	
  $verbose ||=0;
  my $get = dirname(abs_path $0); #get source path
  $connect = $get.'/.connect.txt';
  #setup log file
	$efile = @{ open_unique("db.tad_status.log") }[1];
	$tmpout = @{ open_unique(".export.txt") }[1]; `rm -rf $tmpout`;
	$nosql = @{ open_unique(".nosqlexport.txt") }[1]; `rm -rf $nosql`;
  open(LOG, ">>", $efile) or die "\nERROR:\t cannot write LOG information to log file $efile $!\n";
  print LOG "TransAtlasDB Version:\t",$VERSION,"\n";
  print LOG "TransAtlasDB Information:\tFor questions, comments, documentation, bug reports and program update, please visit $default \n";
  print LOG "TransAtlasDB Command:\t $0 @commandline\n";
  print LOG "TransAtlasDB Started:\t", scalar(localtime),"\n";
}

sub main {
    foreach my $count (0..$#VAR) {
		my $namefile = "tadtmp/tmp_".$tmpname."-".$count.".zzz";
		push $VAR[$count], $namefile;
		while(1) {
			if ($queue->pending() <100) {
				$queue->enqueue($VAR[$count]);
				last;
			}
		}
	}
	foreach(1..5) { $queue-> enqueue(undef); }
}

sub processor {
	my $query;
	while ($query = $queue->dequeue()){
		collectsort(@$query);
	}
}

sub collectsort{
	my $file = pop @_;
	open(OUT2, ">$file");
	foreach (@_){	
		sortposition($_);
	}
	foreach my $genename (sort @_){
		if ($genename =~ /^\S/){
			my ($realstart,$realstop) = split('\|',$REALPOST{$genename},2);
			my $realgenes = (split('\|',$genename))[0];
			print OUT2 $realgenes."\t".$CHROM{$genename}."\:".$realstart."\-".$realstop."\t";
			foreach my $lib (0..$#headers-1){
				if (exists $FPKM{$genename}{$headers[$lib]}){
					print OUT2 "$FPKM{$genename}{$headers[$lib]}\t";
				}
				else {
					print OUT2 "0\t";
				}
			}
			if (exists $FPKM{$genename}{$headers[$#headers]}){
				print OUT2 "$FPKM{$genename}{$headers[$#headers]}\n";
			}
			else {
				print OUT2 "0\n";
			}
		}
  }
}

sub sortposition {
  my $genename = $_[0];
  my $status = "nothing";
	my @newstartarray; my @newstoparray;
	foreach my $libest (sort keys % {$POSITION{$genename}} ) {
		my ($astart, $astop, $status) = VERDICT(split('\|',$POSITION{$genename}{$libest},2));
    push @newstartarray, $astart;
		push @newstoparray, $astop;
		if ($status eq "forward"){
			$realstart = (sort {$a <=> $b} @newstartarray)[0];
			$realstop = (sort {$b <=> $a} @newstoparray)[0];	
		}
		elsif ($status eq "reverse"){
			$realstart = (sort {$b <=> $a} @newstartarray)[0];
			$realstop = (sort {$a <=> $b} @newstoparray)[0];
		}
		else { die "Something is wrong\n"; }
		$REALPOST{$genename} = "$realstart|$realstop";
	}
}

sub VERDICT {
	my (@array) = @_;
	my $status = "nothing";
	my (@newstartarray, @newstoparray);
	if ($array[0] > $array[1]) {
		$status = "reverse";
	}
	elsif ($array[0] < $array[1]) {
		$status = "forward";
	}
	return $array[0], $array[1], $status;
}

sub HEADER {
#header information
	my ($organism, $chrheader) = (@_);
  my $headerinfo = <<"ENDOFFILE";
##fileformat=VCFv4.1
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
##organism="$organism" chromosome="$chrheader"
##INFO=<ID=MTD,Number=.,Type=String,Description="Metadata information from TransAtlasDB. Format:Library|Tissue|Quality|Genotype">
##INFO=<ID=CSQ,Number=.,Type=String,Description="Consequence annotations from Ensembl VEP. Format:Consequence|SYMBOL|Gene|Feature_type|Feature|BIOTYPE|Protein_position|Amino_acids|Codons|Existing_variation|VARIANT_CLASS">
#CHROM    POS    ID    REF    ALT    QUAL    FILTER    INFO    FORMAT    Label
ENDOFFILE
  return $headerinfo;
}

sub PROCESS {
	my @line = @_;
	my $joint = "$line[6]|$line[7]|$line[8]|$line[9]|$line[10]|$line[11]|$line[12]|$line[13]|$line[14]|$line[15]|$line[16]";
	$line[1] = substr($line[1],3);
	$TISSUE{$line[0]} = lc($line[18]);
	$REF{$line[1]}{$line[2]}{$line[3]}{$line[0]} = $line[3];
	$ALT{$line[1]}{$line[2]}{$line[3]}{$line[0]} = $line[4];
	$QUAL{$line[1]}{$line[2]}{$line[3]}{$line[0]} = $line[5];
	if (exists $CSQ{$line[1]}{$line[2]}{$line[3]}{$line[0]}) {
		$number{$line[1]}{$line[2]}{$line[3]}{$line[0]} = $number{$line[1]}{$line[2]}{$line[3]}{$line[0]}++;
		$ODACSQ{$line[1]}{$line[2]}{$line[3]}{$line[0]}{$number{$line[1]}{$line[2]}{$line[3]}{$line[0]}} = $joint;
		$CSQ{$line[1]}{$line[2]}{$line[3]}{$line[0]} =  "$CSQ{$line[1]}{$line[2]}{$line[3]}{$line[0]},$joint";
	}
	else {
		$number{$line[1]}{$line[2]}{$line[3]}{$line[0]}= 1;
		$ODACSQ{$line[1]}{$line[2]}{$line[3]}{$line[0]}{1} = $joint;
		$CSQ{$line[1]}{$line[2]}{$line[3]}{$line[0]} =  $joint;
	}
	my $verdict = undef;
	if ($line[17] =~ /^homozygous/){
		$verdict = '1/1';
	}
	elsif ($line[17] =~ /alternate/){
		$verdict = '1/2';
	}
	elsif ($line[17] =~ /^heterozygous$/){
		$verdict = '0/1';
	}
	else {die "zygosity is blank\n";}
	if (exists $GT{$line[1]}{$line[2]}{$line[3]}{$line[0]}) {
		unless ($GT{$line[1]}{$line[2]}{$line[3]}{$line[0]} =~ $verdict){
			die "Genotype information is different: $verdict is not ",$GT{$line[1]}{$line[2]}{$line[3]}{$line[0]},"contact $AUTHOR\n";
		}
	}
	else {
		$GT{$line[1]}{$line[2]}{$line[3]}{$line[0]} = $verdict;
	}
	if (length($line[15])<1){$line[15]='.';}
	if (exists $DBSNP{$line[1]}{$line[2]}{$line[3]}{$line[0]}) {
		unless ($DBSNP{$line[1]}{$line[2]}{$line[3]}{$line[0]} =~ $line[15]){
			die "DBSNPs information is different: $line[15] is not ",$DBSNP{$line[1]}{$line[2]}{$line[3]}{$line[0]},"contact $AUTHOR\n";
		}
	}
	else {
		$DBSNP{$line[1]}{$line[2]}{$line[3]}{$line[0]} = $line[15];
	}
}


sub SORTER {
  #SORT ALLELES
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %REF) {
    foreach my $position (sort {$a <=> $b} keys %{$REF{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$REF{$chrom}{$position}}) {
        foreach my $library (sort {$a cmp $b || $a <=> $b } keys %{$REF{$chrom}{$position}{$ref}}) {
          if (exists $subref{$chrom}{$position}{$ref}){
            unless ($subref{$chrom}{$position}{$ref} =~ $REF{$chrom}{$position}{$ref}{$library}){
              $subref{$chrom}{$position}{$ref}= $subref{$chrom}{$position}{$ref}.",".$REF{$chrom}{$position}{$ref}{$library};
            }
          }
          else {
            $subref{$chrom}{$position}{$ref}= $REF{$chrom}{$position}{$ref}{$library};
          }
        }
        foreach my $library (sort {$a cmp $b || $a <=> $b} keys %{$ALT{$chrom}{$position}{$ref}}) {
          if (exists $subalt{$chrom}{$position}{$ref}){
            unless ($subalt{$chrom}{$position}{$ref} =~ $ALT{$chrom}{$position}{$ref}{$library}){
              $subalt{$chrom}{$position}{$ref} = $subalt{$chrom}{$position}{$ref}.",".$ALT{$chrom}{$position}{$ref}{$library};
            }
          }
          else {
            $subalt{$chrom}{$position}{$ref}= $ALT{$chrom}{$position}{$ref}{$library};
          }
        }
      }
    }
  }
  
  #sub sort REF & ALT alleles
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %subref) {
    foreach my $position (sort {$a<=> $b} keys %{$subref{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$subref{$chrom}{$position}}) {
        my (%refhash, %althash,$refkey,$altkey);
        my @refarray = split(",", $subref{$chrom}{$position}{$ref});
        foreach (sort {$a cmp $b} @refarray) {$refhash{$_} = $_;}
        foreach (sort {$a cmp $b} keys %refhash){ $refkey .= $_.","; } 
        $NEWREF{$chrom}{$position}{$ref} = substr ($refkey, 1, -1); 
        
        my @altarray = split(",", $subalt{$chrom}{$position}{$ref});
        foreach (sort {$a cmp $b} @altarray) {$althash{$_} = $_;}
        foreach (sort {$a cmp $b} keys %althash){ $altkey .= $_.","; }
        $NEWALT{$chrom}{$position}{$ref} = substr ($altkey, 1,-1);
      }
    }
  }
  
  #SORT CONSEQUENCE
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %CSQ) {
    foreach my $position (sort {$a<=> $b} keys %{$CSQ{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$CSQ{$chrom}{$position}}) {
        foreach my $library (sort {$a cmp $b || $a <=> $b} keys %{$CSQ{$chrom}{$position}{$ref}}) {
          if (exists $NEWCSQ{$chrom}{$position}{$ref}){
            unless ($NEWCSQ{$chrom}{$position}{$ref} =~ $CSQ{$chrom}{$position}{$ref}{$library}){
              die "Consequence should be the same:  $chrom $position not $NEWCSQ{$chrom}{$position}{$ref} equals $CSQ{$chrom}{$position}{$ref}{$library}\n";
            }
          }  
          else {
            $NEWCSQ{$chrom}{$position}{$ref} = $CSQ{$chrom}{$position}{$ref}{$library};
          }
        }
      }
    }
  }
  
  #SORT QUALITY
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %QUAL) {
    foreach my $position (sort {$a<=> $b} keys %{$QUAL{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$QUAL{$chrom}{$position}}) {
        my @quality = undef;
        foreach my $library (sort {$a cmp $b || $a <=> $b} keys %{$QUAL{$chrom}{$position}{$ref}}) {
          push @quality, $QUAL{$chrom}{$position}{$ref}{$library};
        }
        no warnings 'uninitialized';
				@quality = sort {$a <=> $b} @quality;
        $NEWQUAL{$chrom}{$position}{$ref} = $quality[$#quality];
      }
    }
  }
  
  #SORT DBSNP
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %DBSNP) {
    foreach my $position (sort {$a<=> $b} keys %{$DBSNP{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$DBSNP{$chrom}{$position}}) {
        foreach my $library (sort {$a cmp $b || $a <=> $b} keys %{$DBSNP{$chrom}{$position}{$ref}}) {
          if (exists $NEWDBSNP{$chrom}{$position}{$ref}){
            unless ($NEWDBSNP{$chrom}{$position}{$ref} =~ $DBSNP{$chrom}{$position}{$ref}{$library}){
              $NEWDBSNP{$chrom}{$position}{$ref} = '.';
            }
          }  
          else {
            $NEWDBSNP{$chrom}{$position}{$ref} = $DBSNP{$chrom}{$position}{$ref}{$library};
          }
        }
      }
    }
  }
  
  #SORT GENOTYPE
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %GT) {
    foreach my $position (sort {$a<=> $b} keys %{$GT{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$GT{$chrom}{$position}}) {
        foreach my $library (sort {$a cmp $b || $a <=> $b} keys %{$GT{$chrom}{$position}{$ref}}) {
          if (exists $NEWGT{$chrom}{$position}{$ref}){
            unless ($NEWGT{$chrom}{$position}{$ref} =~ $GT{$chrom}{$position}{$ref}{$library}){
              $subgt{$chrom}{$position}{$ref}{$GT{$chrom}{$position}{$ref}{$library}}++;
              #die "Genotype should be the same:  $chrom $position not $NEWGT{$chrom}{$position}{$ref} equals $GT{$chrom}{$position}{$ref}{$library}\n";
            }
          }  
          else {
            $subgt{$chrom}{$position}{$ref}{$GT{$chrom}{$position}{$ref}{$library}} = 1;
            $NEWGT{$chrom}{$position}{$ref} = $GT{$chrom}{$position}{$ref}{$library};
          }
        }
      }
    }
  }
	
  #order genotype
  my %odagt;
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %subgt) {
    foreach my $position (sort {$a<=> $b} keys %{$subgt{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$subgt{$chrom}{$position}}) {
        if ( (exists $subgt{$chrom}{$position}{$ref}{'0/1'}) && (exists $subgt{$chrom}{$position}{$ref}{'1/2'}) ){
          print "yes\t", $chrom,"\t",$position,"\t";
          if ( $subgt{$chrom}{$position}{$ref}{'0/1'} > $subgt{$chrom}{$position}{$ref}{'1/2'} ) {
            print $subgt{$chrom}{$position}{$ref}{'0/1'},"\t0%1\t";
            $subgt{$chrom}{$position}{$ref}{'0/1'} =  $subgt{$chrom}{$position}{$ref}{'0/1'} + $subgt{$chrom}{$position}{$ref}{'1/2'};
            print $subgt{$chrom}{$position}{$ref}{'0/1'},"\n";
          }
          elsif ( $subgt{$chrom}{$position}{$ref}{'0/1'} < $subgt{$chrom}{$position}{$ref}{'1/2'} ) {
            print $subgt{$chrom}{$position}{$ref}{'1/2'},"\t1%2\t";
            $subgt{$chrom}{$position}{$ref}{'1/2'} =  $subgt{$chrom}{$position}{$ref}{'0/1'} + $subgt{$chrom}{$position}{$ref}{'1/2'};
            print $subgt{$chrom}{$position}{$ref}{'1/2'},"\n";
          }
          elsif ( $subgt{$chrom}{$position}{$ref}{'0/1'} == $subgt{$chrom}{$position}{$ref}{'1/2'} ) {
            print $subgt{$chrom}{$position}{$ref}{'0/1'},"\t0%1=\t";
            $subgt{$chrom}{$position}{$ref}{'0/1'} =  $subgt{$chrom}{$position}{$ref}{'0/1'} + $subgt{$chrom}{$position}{$ref}{'1/2'};
            print $subgt{$chrom}{$position}{$ref}{'0/1'},"\n";
                #$subgt{$chrom}{$position}{$ref}{'0/1'} =  $subgt{$chrom}{$position}{$ref}{'0/1'} + $subgt{$chrom}{$position}{$ref}{'1/2'};
          }
          else{die "something is wrong";}
        }
        foreach my $geno (sort {$a cmp $b} keys %{$subgt{$chrom}{$position}{$ref}}){
          $odagt{$chrom}{$position}{$ref}{$subgt{$chrom}{$position}{$ref}{$geno}} = $geno;
        }
      }
    }
  }
  foreach my $chrom (sort {$a cmp $b || $a <=> $b } keys %odagt) {
    foreach my $position (sort {$a <=> $b} keys %{$odagt{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$odagt{$chrom}{$position}}) {
        my $newpost = (sort {$a <=> $b} keys %{$odagt{$chrom}{$position}{$ref}})[0];
        $NEWGT{$chrom}{$position}{$ref} = $odagt{$chrom}{$position}{$ref}{$newpost};
      }
    }
  }
}

sub MTD {
  #get metadata information
  foreach my $chrom (sort {$a cmp $b || $a <=> $b} keys %QUAL) {
    foreach my $position (sort {$a<=> $b} keys %{$QUAL{$chrom}}) {
      foreach my $ref (sort {$a cmp $b} keys %{$QUAL{$chrom}{$position}}) {
        foreach my $library (sort {$a cmp $b || $a <=> $b} keys %{$QUAL{$chrom}{$position}{$ref}}) {
          if (exists $MTD{$chrom}{$position}{$ref}) {
            $MTD{$chrom}{$position}{$ref} = $MTD{$chrom}{$position}{$ref}.",$library|$TISSUE{$library}|$QUAL{$chrom}{$position}{$ref}{$library}|$GT{$chrom}{$position}{$ref}{$library}";
          }
          else {
            $MTD{$chrom}{$position}{$ref} = "$library|$TISSUE{$library}|$QUAL{$chrom}{$position}{$ref}{$library}|$GT{$chrom}{$position}{$ref}{$library}";
          }
        }
      }
    }
  }
}

#--------------------------------------------------------------------------------

=head1 SYNOPSIS

 tad-export.pl [arguments] [-o [-vcf] output-filename]

 Optional arguments:
        -h, --help                      print help message
        -m, --man                       print complete documentation
        -v, --verbose                   use verbose output

	Arguments to retrieve database information
            --query			import metadata file provided
            --db2data                	import data files from gene expression profiling and/or variant analysis

        Arguments for db2data
    	    -x, --excel         	metadata will import the faang excel file provided (default)
	    -t, --tab         		metadata will import the tab-delimited file provided
 
        Arguments to export
            -o, --output	     		data2db will import only the alignment file [TopHat2] and expression profiling files [Cufflinks] (default)
            --vcf           	data2db will import only the alignment file [TopHat2] and variant analysis files [.vcf]



 Function: export data from the database

 Example: #import metadata files
          tad-export.pl --db2data --varanno --species 'Gallus gallus' -o output.txt
					tad-export.pl --db2data --varanno --species 'Gallus gallus' -o -vcf output.txt
					tad-import.pl -metadata -v example/metadata/FAANG/FAANG_GGA_UD.xlsx
          tad-import.pl -metadata -v -t example/metadata/TEMPLATE/metadata_GGA_UD.txt
 	   
	  #import transcriptome analysis data files
	  tad-import.pl -data2db example/sample_sxt/GGA_UD_1004/
	  tad-import.pl -data2db -all -v example/sample_sxt/GGA_UD_1014/
	  tad-import.pl -data2db -variant -annovar example/sample_sxt/GGA_UD_1004/
		
		#delete previously imported data data
	  tad-import.pl -delete GGA_UD_1004


 Version: $Date: 2016-10-28 15:50:08 (Fri, 28 Oct 2016) $

=head1 OPTIONS

=over 8

=item B<--help>

print a brief usage message and detailed explantion of options.

=item B<--man>

print the complete manual of the program.

=item B<--verbose>

use verbose output.

=item B<--metadata>

import metadata file provided.
Metadata files accepted is either a tab-delmited (suffix: '.txt') file 
or FAANG biosamples excel (suffix: '.xls') file

=item B<--tab>

specify the file provided is in tab-delimited format (suffix: '.txt'). (default)

=item B<--excel>

specify the file provided is an excel spreadsheet (suffix: '.xls'/'.xlsx')

=item B<--data2db>

import data files from gene expression profiling analysis 
derived from using TopHat2 and Cufflinks. Optionally 
import variant file (see: variant file format) and 
variant annotation file from annovar or vep.

=item B<--gene>

specify only expression files will be imported. (default)

=item B<--variant>

specify only variant files will be imported.

=item B<--all>

specify both expression and variant files will be imported.

=item B<--vep>

specify annotation file provided was generated using Ensembl Variant Effect Predictor (VEP).

=item B<--annovar>

specify annotation file provided was predicted using ANNOVAR.

=item B<--delete>

delete previously imported information based on sampleid.

=back

=head1 DESCRIPTION

TransAtlasDB is a database management system for organization of gene expression
profiling from numerous amounts of RNAseq data.

TransAtlasDB toolkit comprises of a suite of Perl script for easy archival and 
retrival of transcriptome profiling and genetic variants.

TransAtlasDB requires all analysis be stored in a single folder location for 
successful processing.

Detailed documentation for TransAtlasDB should be viewed on github.

=over 8 

=item * B<directory/folder structure>
A sample directory structure contains file output from TopHat2 software, 
Cufflinks software, variant file from any bioinformatics variant analysis package
such as GATK, SAMtools, and (optional) variant annotation results from ANNOVAR 
or Ensembl VEP in tab-delimited format having suffix '.multianno.txt' and '.vep.txt' 
respectively. An example is shown below:

	/sample_name/
	/sample_name/tophat_folder/
	/sample_name/tophat_folder/accepted_hits.bam
	/sample_name/tophat_folder/align_summary.txt
	/sample_name/tophat_folder/deletions.bed
	/sample_name/tophat_folder/insertions.bed
	/sample_name/tophat_folder/junctions.bed
	/sample_name/tophat_folder/prep_reads.info
	/sample_name/tophat_folder/unmapped.bam
	/sample_name/cufflinks_folder/
	/sample_name/cufflinks_folder/genes.fpkm_tracking
	/sample_name/cufflinks_folder/isoforms.fpkm_tracking
	/sample_name/cufflinks_folder/skipped.gtf
	/sample_name/cufflinks_folder/transcripts.gtf
	/sample_name/variant_folder/
	/sample_name/variant_folder/<filename>.vcf
	/sample_name/variant_folder/<filename>.multianno.txt
	/sample_name/variant_folder/<filename>.vep.txt

=item * B<variant file format>

A sample variant file contains one variant per line, with the fields being chr,
start, end, reference allele, observed allele, other information. The other
information can be anything (for example, it may contain sample identifiers for
the corresponding variant.) An example is shown below:

        16      49303427        49303427        C       T       rs2066844       R702W (NOD2)
        16      49314041        49314041        G       C       rs2066845       G908R (NOD2)
        16      49321279        49321279        -       C       rs2066847       c.3016_3017insC (NOD2)
        16      49290897        49290897        C       T       rs9999999       intronic (NOD2)
        16      49288500        49288500        A       T       rs8888888       intergenic (NOD2)
        16      49288552        49288552        T       -       rs7777777       UTR5 (NOD2)
        18      56190256        56190256        C       T       rs2229616       V103I (MC4R)

=item * B<invalid input>

If any of the files input contain invalid arguments or format, TransAtlas 
will terminate the program and the invalid input with the outputted. 
Users should manually examine this file and identify sources of error.

=back


--------------------------------------------------------------------------------

TransAtlasDB is free for academic, personal and non-profit use.

For questions or comments, please contact $ Author: Modupe Adetunji <amodupe@udel.edu> $.

=cut

