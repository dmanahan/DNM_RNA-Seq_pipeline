organism=$1
feature=$2

################################################################################################################
#PRODUCING PROTEIN CODE GENE LIST AND GENE LENGTHS
################################################################################################################
if [ ${organism} = 'hg38' ]; then
  path_to_gtf='../../genome_references/gencode.v27.annotation.gtf'
elif [ ${organism} = 'Rnor6' ]; then
  path_to_gtf='../../genome_references/Rattus_norvegicus.Rnor_6.0.91.chr.gtf'
elif [ ${organism} = 'mg38' ]; then
  path_to_gtf='../../genome_references/gencode.vM16.annotation.gtf'
else
  echo 'Please specify whether your are querying human, rat, or mouse RNA-Seq count matrices'
fi

#From the .gtf file, create a text file with ONLY protein coding genes.
echo 'Extracting information on protein-coding genes from gtf...'
cat ${path_to_gtf} | grep 'protein' > output0.txt

if [ ${feature} = 'CDS' ]; then
  #Extract CDS region information ONLY
  cat output0.txt | grep 'CDS' > output1.txt
  sed -i '/CCDS/d' output1.txt
elif [ ${feature} = 'gene' ]; then
  #Extract gene information ONLY
  sed '/transcript/d' output0.txt > output1.txt
elif [ ${feature} = 'transcript' ]; then
  #Extract transcript information ONLY
  cat output0.txt | grep 'transcript' > output1.txt
  sed -i '/exon/d' output1.txt
else
  echo 'Please specify whether you want genes, transcripts, or CDS regions to serve as your reference.'
fi

#Extract the ENSEMBL gene name and gene length from .txt.  NOTE that transcripts will be assigned to same gene name and will appear as duplicates.
echo 'Extracting ENSEMBL gene name and gene length...'
awk '{print $10 "\t" ($5 - $4)}' output1.txt > output2.txt

echo 'Formating gene names and gene lengths...'
#Remove all quotes from our protein coding gene list.
sed -i 's/\"//g' output2.txt

#Remove all semicolons from our ptoein coding gene list.
sed -i 's/;//g' output2.txt

#Remove all decimals from our protein coding gene list.  Decimals indicate splicing variants.
sed -i 's/\.[0-9]*//' output2.txt

#Combine duplicate ENSEMBL IDs and average their gene length
echo 'Averaging combined gene lengths of duplicate ENSEMBL IDs'
awk '
    NR>1{
        arr[$1]   += $2
        count[$1] += 1
    }
    END{
        for (a in arr) {
            print a " " arr[a] / count[a]
        }
    }
' output2.txt > output3.txt

#Sort the protein coding ENSEMBL IDs and gene lengths alphabetically by ENSEMBL ID.
echo 'Sorting protein-coding ENSEMBL IDs and gene lengths alphatibetically by ENSEMBL ID...'
sort output3.txt > coding_gene_lengths_${feature}.txt
sed -i '/__/d' coding_gene_lengths_${feature}.txt
awk '{$2=""; print $0}' coding_gene_lengths_${feature}.txt > coding_genes_${feature}.txt

################################################################################################################
#USING PROTEIN-CODING GENE LIST AS A REFERENCE TO EXTRACT PROTEIN-CODING GENES FROM RNA-SEQ COUNT MATRICES
################################################################################################################

#Extract protein-coding genes from your HTSeq-count file
echo 'Extracting protein-coding genes from HTSeq-count output...'
for i in $(cat ../accession_list); do
  for j in $(cat coding_genes_${feature}.txt); do cat ../HTSeq/count_${i}.txt | grep ${j} >> output_${i}.txt; done;
done

#Sort the curated count matrices
echo 'Sorting extracted protein-coding genes from HTSeq-count output...'

for i in $(cat ../accession_list); do
  sort output_${i}.txt > curated_count_${i}_${feature}.txt
done

#Remove intermediate files
rm output*

################################################################################################################
#NORMALIZING RAW RNA-SEQ COUNT DATA WITH TPM USING THE PROTEIN-CODING GENE LENGTHS LIST
################################################################################################################

for i in $(cat ../accession_list); do
  ../../TPM.sh curated_count_${i}_${feature}.txt ${feature};
done
[dmanahan@hpc-cmb RNA-Seq_pipeline]$ cat TPM.sh
filename=$1
feature=$2


#Create a file with a single column of gene lengths sorted in the order as your RNA-Seq count matrix.
#Print and store the gene lengths column
awk '{print $2}' ../Protein-coding_matrices/coding_gene_lengths_${feature}.txt > TPM_output1.txt

#Divide each gene length by 1000 to convert from bases to kilobases and then concatenate an extra column
awk '{$2 = $1 / 1000}1' TPM_output1.txt > TPM_output2.txt
#Print and store all gene lengths in kilobases
awk '{print $2}' TPM_output2.txt > coding_gene_lengths_only.txt

#Concatenate the gene length column to your RNA-Seq count matrix
pr -mts' ' ${filename} coding_gene_lengths_only.txt > TPM_output3.txt

#Divide each raw count by its respective gene length and concatenate the output in a new column.  This gives you a column with RPK values.

awk '{$4 = $2 / $3}1' TPM_output3.txt > TPM_output4.txt

#Sum up all RPK values
RPK=$(awk '{s+=$4}END{print s}' TPM_output4.txt)

#Convert RPK to a format that bc can read.  bc cannot read the scientific notation output as is.
value=`echo ${RPK} | sed -e 's/[eE]+*/\\*10\\^/'`

#Divide RPK by 1,000,000 to get the "per million" scaling factor
echo "scale = 6; ${value} / 1000000" | bc > TPM_output_scaling_factor.txt
scaling_factor=$(cat TPM_output_scaling_factor.txt)
