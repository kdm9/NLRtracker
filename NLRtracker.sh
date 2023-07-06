#!/bin/bash

# directory name
dir_name="$(readlink -f "$(dirname "$0")")"

# help
function usage {
  cat <<EOM
Usage: $(basename "$0") [OPTION]...
  -h               Display help
  (required)
  -s Filepath      File path to amino acid(/nucleotide seqence) file (.fasta)
                   nucleotide seqence requires -t option.
  -o String        Directory name to save output

  (optional)
  -i Filepath      Result of Interproscan (.gff3)
  -f Filepath      Result of FIMO (.gff)
  -M Filepath      Result of CJID hmmscan (.txt)
  -t String        Seqtype of fasta file. dna/rna ("n") or protein ("p")
                   Default: "p"
  -c Integer       Number of CPUs for interproscan
                   Default: 2
  -m Filepath      meme.xml for use with FIMO
                   Default: module/meme.xml (from NLR Annotator)
  -x Filepath      hmm for use with HMMER
                   Default: module/abe3069_Data_S1.hmm (from Ma et al., 2020)
  -d Filepath      Description of Interproscan
                   Default: module/InterProScan 5.53-87.0.list
EOM
  exit 2 
}

# check options
echo -e "\n---------------------- input & option -----------------------";
while getopts ":s:i:f:t:c:m:x:d:o:h" optKey; do
  case "$optKey" in
    s)
      if [ -f ${OPTARG} ]; then
        echo "Fasta file             = ${OPTARG}"
        fasta=${OPTARG}
        origfasta=${OPTARG}
        FLG_S=1
      else
        echo "${OPTARG} does not exits."
      fi
      ;;
    i)
      if [ -f ${OPTARG} ]; then
        echo "result of interproscan = ${OPTARG}"
        interpro_result=${OPTARG}
        FLG_I=1
      else
        echo "${OPTARG} does not exits. Run interproscan in this pipeline."
      fi
      ;;
    f)
      if [ -f ${OPTARG} ]; then
        echo "result of FIMO         = ${OPTARG}"
        FIMO_result=${OPTARG}
        FLG_F=1
      else
        echo "${OPTARG} does not exits. Run FIMO in this pipeline."
      fi
      ;;
    M)
      if [ -f ${OPTARG} ]; then
        echo "result of HMMscan for CJID        = ${OPTARG}"
        hmmscan_result=${OPTARG}
        FLG_bigM=1
      else
        echo "${OPTARG} does not exits. Run hmmscan in this pipeline."
      fi
      ;;
    t)
      echo "Seqtype of fasta       = ${OPTARG}"
      Seqtype=${OPTARG}
      ;;
    c)
      echo "Number of CPUs         = ${OPTARG}"
      CPU=${OPTARG}
      ;;
    m)
      echo "xml for FIMO           = ${OPTARG}"
      XML=${OPTARG}
      ;;
    x)
      echo "hmm for HMMER           = ${OPTARG}"
      HMM=${OPTARG}
      ;;
    d)
      echo "Description of Interpro = ${OPTARG}"
      Int_Desc=${OPTARG}
      ;;
    o)
      FLG_O=1
      echo "output directory       = ${OPTARG}"
      outdir=${OPTARG}
      ;;
    '-h'|'--help'|* )
        usage
      ;;
  esac
done
echo -e "\n---------------------- input & option -----------------------";

# check fasta file
if [ -z "$FLG_S" ]; then
  echo -e "$(basename $0) : -s option is required\n"
  usage
  exit 1
fi

# check header
if [ -z "$FLG_O" ]; then
  echo -e "$(basename $0) : -o option is required\n"
  usage
  exit 1
fi

# Main pipeline
test -d "${outdir}" || mkdir $outdir
cat $fasta | awk '{if ($1 ~ /^>/) print "\n"$1; else printf $1}' | sed -e '1d' > ${outdir}/tmp.fasta
fasta=${outdir}/tmp.fasta

# 1. Interproscan
if [ -z "$FLG_I" ]; then
  interpro_result="${outdir}/interpro_result.gff"
  if [ "${interpro_result}" -ot "${origfasta}" ]
  then
      echo -e "\nRun Interproscan"
      interproscan.sh -version
      echo -e "\ninterproscan.sh -i $fasta -f gff3 -t ${Seqtype:-p} -o ${outdir}/interpro_result.gff -cpu ${CPU:-2} -appl Pfam,Gene3D,SUPERFAMILY,PRINTS,SMART,CDD,ProSiteProfiles"
      interproscan.sh -i $fasta -f gff3 -t ${Seqtype:-"p"} -o "${interpro_result}" -cpu ${CPU:-2} -appl Pfam,Gene3D,SUPERFAMILY,PRINTS,SMART,CDD,ProSiteProfiles -dp
  else
      echo -e "\nSKIP interproscan.sh -- output exists, remove ${interpro_result} to rerun"
  fi
else
  echo -e "\nPass Interproscan (Use $interpro_result as output of Interproscan)"
fi

# 2. FIMO
if [ -z "$FLG_F" ]; then
    FIMO_result="${outdir}/fimo_out/fimo.gff"
    if [ "${FIMO_result}" -ot "${origfasta}" ]
    then
        echo -e "\nRun FIMO"
        echo -e "\nfimo -o ${outdir}/fimo_out ${XML:-${dir_name}/module/meme.xml} $fasta"
        fimo -o "${outdir}/fimo_out" ${XML:-"${dir_name}/module/meme.xml"} $fasta
    else
        echo -e "\nSKIP FIMO motif search -- output exists, remove ${FIMO_result} to rerun"
    fi
else
  echo -e "\nPass FIMO (Use $FIMO_result as output of FIMO)"
fi

# 3. HMMER hmmsearch
if [ "${Seqtype:-p}" == "p" ]; then
    hmmer_result="${outdir}/CJID.txt"
    if [ "${hmmer_result}" -ot "${origfasta}" ]
    then
        echo -e "\nRun HMMER"
        echo -e "\nhmmsearch --domtblout ${outdir}/CJID.txt ${HMM:-"${dir_name}/module/abe3069_Data_S1.hmm"} $fasta"
        hmmsearch --domtblout "${hmmer_result}" ${HMM:-"${dir_name}/module/abe3069_Data_S1.hmm"} $fasta
    else
        echo -e "\nSKIP hmmsearch -- output exists, remove ${hmmer_result} to rerun."
    fi
else
  echo -e "hmmsearch not executed"
fi

# 4. NLR_extractor.R
if [ -f $interpro_result -a -f $FIMO_result ]; then
  echo -e "\nRun NLRtracker"
  Rscript --vanilla ${dir_name}/module/NLRtracker.R ${Int_Desc:-"${dir_name}/module/InterProScan 5.53-87.0.list"} $interpro_result $FIMO_result ${fasta} $outdir ${Seqtype:-"p"} $hmmer_result $"${dir_name}/module/iTOL_NLR_template.txt"
  echo -e "\nFinish NLRtracker!"
  rm -rf ${outdir}tmp.fasta
else
  echo -e "\nInterproscan output or FIMO output don't exist."
  exit 1
fi
