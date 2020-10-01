#Author: Renato Oliveira
#version: 1.0
#Date: 01-10-2020

###    Copyright (C) 2020  Renato Oliveira
###
###    This program is free software: you can redistribute it and/or modify
###    it under the terms of the GNU General Public License as published by
###    the Free Software Foundation, either version 3 of the License, or
###    any later version.
###
###    This program is distributed in the hope that it will be useful,
###    but WITHOUT ANY WARRANTY; without even the implied warranty of
###    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
###    GNU General Public License for more details.
###
###    You should have received a copy of the GNU General Public License
###    along with this program.  If not, see <http://www.gnu.org/licenses/>.

###Contacts:
###    ronnie.alves@itv.org
###    renato.renison@gmail.com or renato.oliveira@pq.itv.org

#!/bin/bash
#usage for Illumina Data: ./assembly_docker.sh -i illumina -1 <forward_reads> -2 <reverse_reads> -r <ref_fasta> -k <kmer_decontamination> -m <max_mismatch> -l <min_length> -c <min_coverage> -o <output_folder> -s <sample_name> -t <threads>
#-i = Sequencinf platform. Either "illumina" or "pacbio"
#-1 = path to the forward reads.
#-2 = path to the reverse reads.
#-k = Kmer to use in decontamination when comparing to the reference fasta. Default is 31.
#-m = Maximum of mismatch to accept in the kmers. Default is 2.
#-l = Minimum length for sequence filtering
#-c = Minimum coverage for sequence filtering
#-r = Reference file to use in decontamination
#-o = folder where all the results will be saved. Default is "output"
#-s = Sample name. Default is "sample"
#-t = number of threads to use in the analisys. Default is 1.
#Example = ./assembly_docker.sh -i illumina -1 output_qc/SRR11587600_good.pair1.truncated -2 output_qc/SRR11587600_good.pair2.truncated -r sars-cov-2_MN908947.fasta -k 31 -m 2 -o output_assembly -t 24 -s illumina_rtpcr

KMER="31"
MAX_MISMATCH="2"
OUTPUT="output"
SAMPLE_NAME="sample"
THREADS="1"
MIN_LENGTH="100"
MIN_COVERAGE="10"

while getopts "i:1:2:k:r:s:l:c:o:t:m:" opt; do
	case $opt in
		i) SEQUENCER="$OPTARG"
		;;
		1) FORWARD_READS="$OPTARG"
		;;
		2) REVERSE_READS="$OPTARG"
		;;
		k) KMER="$OPTARG"
		;;
		m) MAX_MISMATCH="$OPTARG"
		;;
		r) REF="$OPTARG"
		;;
		s) SAMPLE_NAME="$OPTARG"
		;;
		o) OUTPUT="$OPTARG"
		;;
		t) THREADS="$OPTARG"
		;;
		l) MIN_LENGTH="$OPTARG"
		;;
		c) MIN_COVERAGE="$OPTARG"
		;;
		\?) echo "Invalid option -$OPTARG" >&2
    	;;
	esac
done

CURRENT_PATH=$(pwd)

if [ ! -d $OUTPUT ]; then
	mkdir $OUTPUT
fi

if [ $SEQUENCER = "illumina" ];
then

	DIR_NAME_FOR=$(dirname $FORWARD_READS)
	cd $DIR_NAME_FOR
	FULL_PATH_FOR=$(pwd)
	cd $CURRENT_PATH

	DIR_NAME_REV=$(dirname $REVERSE_READS)
	cd $DIR_NAME_REV
	FULL_PATH_REV=$(pwd)
	cd $CURRENT_PATH

	DIR_NAME_REF=$(dirname $REF)
	cd $DIR_NAME_REF
	FULL_PATH_REF=$(pwd)
	cd $CURRENT_PATH

	COMMON_PATH=$({ echo $FULL_PATH_FOR; echo $FULL_PATH_REV; echo $FULL_PATH_REF;} | sed -e 'N;s/^\(.*\).*\n\1.*$/\1\n\1/;D')
	FORWARD_READS=$(echo ${FULL_PATH_FOR#"$COMMON_PATH"})/$(basename $FORWARD_READS)
	REVERSE_READS=$(echo ${FULL_PATH_REV#"$COMMON_PATH"})/$(basename $REVERSE_READS)
	REF=$(echo ${FULL_PATH_REF#"$COMMON_PATH"})/$(basename $REF)
	newfile="$(basename $FORWARD_READS)"
	newfile="${newfile%%_*}"
	newfile="${newfile%%.*}"

	# echo "Current path: '$CURRENT_PATH'"
	# echo "Common path: '$COMMON_PATH'"


	# #Filtering contaminants 
	echo "Creating a BBDuk Container: "
	docker run -id -v $COMMON_PATH:/bbduk/ -v $CURRENT_PATH:/output/ --name bbduk itvds/covid19_bbtools:BBMap.38.76

	matched_fastq1='/output/'$OUTPUT'/1-decontamination_out/'$SAMPLE_NAME'_matched_r1.fastq'
	matched_fastq2='/output/'$OUTPUT'/1-decontamination_out/'$SAMPLE_NAME'_matched_r2.fastq'
	unmatched_fastq1='/output/'$OUTPUT'/1-decontamination_out/'$SAMPLE_NAME'_unmatched_r1.fastq' 
	unmatched_fastq2='/output/'$OUTPUT'/1-decontamination_out/'$SAMPLE_NAME'_unmatched_r2.fastq' 
	filter_stats='/output/'$OUTPUT'/1-decontamination_out/'$SAMPLE_NAME'_stats_filtering.txt'
		
	#echo "Running BBDuk Container: "

	docker exec -i bbduk /bin/bash -c "mkdir -p /output/'$OUTPUT'/1-decontamination_out; \
	 		bbduk.sh -Xmx80g in1=/bbduk/'$FORWARD_READS' in2=/bbduk/'$REVERSE_READS' out1=$unmatched_fastq1 out2=$unmatched_fastq2 outm1=$matched_fastq1 outm2=$matched_fastq2 ref=/bbduk/'$REF' k=$KMER hdist=$MAX_MISMATCH stats=$filter_stats overwrite=TRUE t=$THREADS ;\
	 		chmod -R 777 /output/'$OUTPUT'"

	#Alignin with Bowtie
	echo "Creating a Bowtie Container: "
	docker run -id -v $COMMON_PATH:/bowtie/ -v $CURRENT_PATH:/output/ --name bowtie itvds/covid19_bowtie2:latest

	echo "Running the Bowtie Container: "
	docker exec -i bowtie  /bin/bash -c "mkdir /output/'$OUTPUT'/2-bowtie_out; cd /output/'$OUTPUT'/2-bowtie_out ; \
			/NGStools/bowtie2-2.3.5.1-linux-x86_64/bowtie2-build /bowtie/'$REF' .'$REF'; \
			/NGStools/bowtie2-2.3.5.1-linux-x86_64/bowtie2 -x .'$REF' --no-unal -1 /bowtie/'$FORWARD_READS' -2 /bowtie/'$REVERSE_READS' -p $THREADS > bowtie_output; \
			chmod -R 777 /output/'$OUTPUT'/2-bowtie_out"

	#Starting with SAMTOOLS
	echo "Creating a SAMTOOLS Container: "
	docker run -id -v $COMMON_PATH:/samtools/ -v $CURRENT_PATH:/output/ --name samtools itvds/covid19_samtools:latest

	mappedtoref_bam='/output/'$OUTPUT'/3-samtools_out/'$SAMPLE_NAME'.bam'

	echo "Running the SAMTOOLS Container: "
	docker exec -i samtools  /bin/bash -c "mkdir /output/'$OUTPUT'/3-samtools_out; cd /output/'$OUTPUT'/3-samtools_out ; \
			samtools view -bS -@ $THREADS /output/'$OUTPUT'/2-bowtie_out/bowtie_output > $mappedtoref_bam; \
			samtools sort -@ $THREADS -o /output/'$OUTPUT'/3-samtools_out/'$SAMPLE_NAME'.sorted.bam $mappedtoref_bam; \
			rm $mappedtoref_bam; mv /output/'$OUTPUT'/3-samtools_out/'$SAMPLE_NAME'.sorted.bam $mappedtoref_bam; \
			chmod -R 777 /output/'$OUTPUT'/3-samtools_out"

	#Assembling with SPAdes
	echo "Creating a Spades Container: "
	docker run -id -v $COMMON_PATH:/spades/ -v $CURRENT_PATH:/output/ --name spades itvds/covid19_spades:v3.11.1
	
	echo "Running the Spades Container"
	docker exec -i spades /bin/bash -c "mkdir /output/'$OUTPUT'/4-spades_out; cd /output/'$OUTPUT'/4-spades_out; \
		spades.py -1 $matched_fastq1 -2 $matched_fastq2 -o ./'$SAMPLE_NAME' --careful -t $THREADS; \
		chmod -R 777 /output/'$OUTPUT'/4-spades_out"


	#GEnerating consensus with R scripts
	echo "Creating a R Container: "
	docker run -id -v $COMMON_PATH:/rdocker/ -v $CURRENT_PATH:/output/ --name rdocker itvds/covid19_r:latest bash
	#docker run -id -v $COMMON_PATH:/rdocker/ -v $CURRENT_PATH:/output/ --name rdocker covid19_r bash
	
	scaffname="/output/'$OUTPUT'/4-spades_out/'$SAMPLE_NAME'/scaffolds.fasta"
	scaffname_ln="scaffolds.fasta"
	if [ ! -f "/'$OUTPUT'/4-spades_out/'$SAMPLE_NAME'/scaffolds.fasta" ]; then 
		cp ${OUTPUT}/4-spades_out/${SAMPLE_NAME}/contigs.fasta ${OUTPUT}/4-spades_out/${SAMPLE_NAME}/scaffolds.fasta
	fi

	echo "Running the R Container"
	docker exec -i rdocker /bin/bash -c " mkdir /output/'$OUTPUT'/5-rscripts; cd /output/'$OUTPUT'/5-rscripts; ln $scaffname . ;\
		Rscript --vanilla /Scripts/hcov_make_seq.R sampname=\\\"$SAMPLE_NAME\\\" reffname=\\\"/rdocker/'$REF'\\\" scaffname=\\\"$scaffname_ln\\\" minlength=\\\"$MIN_LENGTH\\\" mincoverage=\\\"$MIN_COVERAGE\\\" ncores=\\\"$THREADS\\\"; \
		chmod -R 777 /output/'$OUTPUT'/5-rscripts"

	#Aligning with BWA
	echo "Creating a BWA Container: "
	docker run -id -v $COMMON_PATH:/bwa/ -v $CURRENT_PATH:/output/ --name bwadocker itvds/covid19_bwa:latest
	
	echo "Running the BWA Container"
	docker exec -i bwadocker /bin/bash -c "cd /output/'$OUTPUT'/5-rscripts;  bwa index /bwa/'$REF';\
		bwa mem /bwa/'$REF' scaffolds_filtered.fasta > '$SAMPLE_NAME'_aligned_scaffolds_toRef.sam;\
		mv /bwa/'$REF'.* /output/'$OUTPUT'/5-rscripts; chmod -R 777 /output/'$OUTPUT'/5-rscripts"

	#Converting with samtools
	echo "Running the SAMTOOLS Container: "
	docker exec -i samtools  /bin/bash -c "cd /output/'$OUTPUT'/5-rscripts ; \
			samtools view -bh -@ $THREADS -o /output/'$OUTPUT'/5-rscripts/'$SAMPLE_NAME'_aligned_scaffolds_toRef.bam '$SAMPLE_NAME'_aligned_scaffolds_toRef.sam -T /samtools/'$REF'; \
			samtools sort -@ $THREADS -o /output/'$OUTPUT'/5-rscripts/'$SAMPLE_NAME'_aligned_scaffolds_toRef.sorted.bam '$SAMPLE_NAME'_aligned_scaffolds_toRef.bam; \
			chmod -R 777 /output/'$OUTPUT'/5-rscripts"

	# # Continuing to generate consensus with R scripts	
	scaffname='/output/'$OUTPUT'/4-spades_out/'$SAMPLE_NAME'/scaffolds.fasta'
	echo "Running the R Container"
	docker exec -i rdocker /bin/bash -c "cd /output/'$OUTPUT'/5-rscripts;\
		Rscript --vanilla /Scripts/hcov_make_seq2.R bamfname=\\\"/output/'$OUTPUT'/5-rscripts/'$SAMPLE_NAME'_aligned_scaffolds_toRef.sorted.bam\\\" reffname=\\\"/rdocker/'$REF'\\\" ncores=\\\"$THREADS\\\" ;\
		chmod -R 777 /output/'$OUTPUT'/5-rscripts"

	#Aligning to the first consensus with Bowtie
	consensus='/output/'$OUTPUT'/5-rscripts/ref_for_remapping/'$SAMPLE_NAME'_aligned_scaffolds_toRef.sorted_consensus.fasta'
	echo "Running the Bowtie Container: "
	docker exec -i bowtie  /bin/bash -c "mkdir /output/'$OUTPUT'/6-bowtie_out2; cd /output/'$OUTPUT'/6-bowtie_out2 ; \
			/NGStools/bowtie2-2.3.5.1-linux-x86_64/bowtie2-build $consensus $consensus ;\
			/NGStools/bowtie2-2.3.5.1-linux-x86_64/bowtie2 -x $consensus --no-unal -1 $matched_fastq1 -2 $matched_fastq2 -p $THREADS > bowtie_output; \
			chmod -R 777 /output/'$OUTPUT'/6-bowtie_out2; chmod -R 777 /output/'$OUTPUT'/5-rscripts/ref_for_remapping/"

	# # #Starting with SAMTOOLS
	remappedtoref_bam='/output/'$OUTPUT'/7-samtools_out2/'$SAMPLE_NAME'.bam'

	 echo "Running the SAMTOOLS Container: "
	 docker exec -i samtools  /bin/bash -c "mkdir /output/'$OUTPUT'/7-samtools_out2; cd /output/'$OUTPUT'/7-samtools_out2 ; \
	 		samtools view -bS -@ $THREADS /output/'$OUTPUT'/6-bowtie_out2/bowtie_output > $remappedtoref_bam; \
	 		samtools sort -@ $THREADS -o /output/'$OUTPUT'/7-samtools_out2/'$SAMPLE_NAME'.sorted.bam $remappedtoref_bam; \
	 		rm $remappedtoref_bam; mv /output/'$OUTPUT'/7-samtools_out2/'$SAMPLE_NAME'.sorted.bam $remappedtoref_bam; \
	 		chmod -R 777 /output/'$OUTPUT'/7-samtools_out2"


	#Generating final consensus with R scripts
	echo "Running the R Container"
	docker exec -i rdocker /bin/bash -c "mkdir /output/'$OUTPUT'/8-final_consensus; cd /output/'$OUTPUT'/8-final_consensus; \
		mkdir -p ./consensus_seqs; mkdir -p ./stats; \
		Rscript --vanilla /Scripts/hcov_generate_consensus.R sampname=\\\"$SAMPLE_NAME\\\" ref=\\\"/rdocker/'$REF'\\\" remapped_bamfname=\\\"$remappedtoref_bam\\\" mappedtoref_bamfname=\\\"$mappedtoref_bam\\\" ;\
		cp consensus_seqs/'$SAMPLE_NAME'.fasta ../; mv /rdocker/'$REF'.* . ; \
		chmod -R 777 /output/'$OUTPUT'/8-final_consensus "


	# #Annotation with Prokka
	echo "Creating a Prokka Container: "
	docker run -id -v $COMMON_PATH:/prokka/ -v $CURRENT_PATH:/output/ --name prokka itvds/covid19_prokka:latest
	
	echo "Running the Prokka Container"
	docker exec -i prokka /bin/bash -c "mkdir /output/'$OUTPUT'/9-prokka_annotation; cd /output/'$OUTPUT'/9-prokka_annotation; \
		prokka --outdir ./'$SAMPLE_NAME'/ --force --kingdom Viruses --genus Betacoronavirus --usegenus --prefix $SAMPLE_NAME /output/'$OUTPUT'/8-final_consensus/consensus_seqs/'$SAMPLE_NAME'.fasta; \
		chmod -R 777 /output/'$OUTPUT'/9-prokka_annotation; cp '$SAMPLE_NAME'/'$SAMPLE_NAME'.g* ../; \
		chmod -R 777 /output/'$OUTPUT'/3-samtools_out/ ; chmod -R 777 /output/'$OUTPUT'/7-samtools_out2; \
		chmod -R 777 /output/'$OUTPUT'/;"



fi

echo "Stopping Containeres: "
docker stop bbduk
docker stop bowtie
docker stop samtools
docker stop rdocker
docker stop spades
docker stop bwadocker
docker stop prokka

echo "Removing Containeres: "
docker rm bbduk
docker rm bowtie
docker rm samtools
docker rm rdocker
docker rm spades
docker rm bwadocker
docker rm prokka

echo "Done!"