#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat << EOF
Usage:
	$(basename "$0") \
		-i samples.tsv \
		-o genomes \
		-f failed_biosamples.txt \
		-c container.sif

Input TSV must contain columns:
	Strain
	Biosample

Options:
	-i  Input TSV [default: biosamples.tsv]
	-o  Output directory for genomes [default: genomes]
	-r  Output directory for reads [default: sra_reads]
	-f  Failed BioSamples file [default: failed_biosamples.txt]
	-c  Singularity container [default: /home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif]
	-d  Singularity container for SRA tools [default: /home/vasarhelyib/containers/ncbi-sra-tools.3.4.1.sif]
	-t  Output table with assembly paths [default: assemblies.tsv]
	-n  Number of threads for fasterq-dump [default: 8]
	-p  Maximum concurrent NCBI assembly downloads [default: 8]
	-h  Show this help message
	-s  Skip assembly download phase and run only fasterq-dump on entries in failed file
	-u Skip assembly download phase and fasterq-dump, just prepare the assembly input table for the assembler with the entries in the failed file
EOF
	exit 1
}

SKIP_TO_FASTERQ=0
SKIP_TO_ASSEMBLY=0
DOWNLOAD_JOBS=8
INPUT="biosamples.tsv"
OUTDIR="genomes"
FAILED="failed_biosamples.txt"
CONTAINER="/home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif"
SRA_CONTAINER="/home/vasarhelyib/containers/ncbi-sra-tools.3.4.1.sif"
READDIR="sra_reads"


OUTPUT_TABLE="assemblies.tsv"
THREADS=8

while getopts ":i:o:r:f:c:d:t:n:p:suh" opt; do
	case "${opt}" in
		i) INPUT="${OPTARG}" ;;
		o) OUTDIR="${OPTARG}" ;;
		r) READDIR="${OPTARG}" ;;
		f) FAILED="${OPTARG}" ;;
		c) CONTAINER="${OPTARG}" ;;
		d) SRA_CONTAINER="${OPTARG}" ;;
		t) OUTPUT_TABLE="${OPTARG}" ;;
		n) THREADS="${OPTARG}" ;;
		p) DOWNLOAD_JOBS="${OPTARG}" ;;
		s) SKIP_TO_FASTERQ=1 ;;
		u) SKIP_TO_ASSEMBLY=1 ;;
		h) usage ;;
		*) usage ;;
	esac
done



# if [[ "$SKIP_TO_FASTERQ" -eq 0 ]]; then

# 	mkdir -p "${OUTDIR}"
# 	: > "${FAILED}"
# 	echo -e "Sample_ID\tBiosample\tSpecies\tR1\tR2\tAssembly" > "${FAILED}"

# 	HEADER=$(head -n1 "${INPUT}")
# 	echo -e "${HEADER}\tAssembly" > "${OUTPUT_TABLE}"

# 	STRAIN_COL=$(echo "${HEADER}" | tr '\t' '\n' | nl -v1 | awk '$2=="Sample_ID"{print $1}')
# 	BIOSAMPLE_COL=$(echo "${HEADER}" | tr '\t' '\n' | nl -v1 | awk '$2=="Biosample"{print $1}')
# 	SPECIES_COL=$(echo "${HEADER}" | tr '\t' '\n' | nl -v1 | awk '$2=="Species"{print $1}')

# 	[[ -z "${STRAIN_COL}" ]] && { echo "Column 'Sample_ID' not found"; exit 1; }
# 	[[ -z "${BIOSAMPLE_COL}" ]] && { echo "Column 'Biosample' not found"; exit 1; }
# 	[[ -z "${SPECIES_COL}" ]] && { echo "Column 'Species' not found"; exit 1; }

# 	tail -n +2 "${INPUT}" | while IFS= read -r LINE; do

# 		IFS=$'\t' read -r -a FIELDS <<< "${LINE}"

# 		STRAIN="${FIELDS[$((STRAIN_COL - 1))]}"
# 		BIOSAMPLE="${FIELDS[$((BIOSAMPLE_COL - 1))]}"
# 		SPECIES="${FIELDS[$((SPECIES_COL - 1))]}"
# 		[[ -z "${STRAIN}" ]] && continue
# 		[[ -z "${BIOSAMPLE}" ]] && continue
# 		[[ -z "${SPECIES}" ]] && continue

# 		OUTFILE="${OUTDIR}/${STRAIN}.fna.gz"
# 		echo -e "${LINE}\t${OUTFILE}" >> "${OUTPUT_TABLE}"

# 		if [[ -s "${OUTFILE}" ]]; then
# 			echo "SKIP (exists): ${STRAIN}"

# 			continue
# 		fi

# 		echo "Processing: ${STRAIN} (${BIOSAMPLE})"

# 		URL=$(
# 			singularity exec \
# 				</dev/null \
# 				--env LC_ALL=C,LANG=C,LANGUAGE=C,NCBI_API_KEY="${NCBI_API_KEY:-}" \
# 				"${CONTAINER}" \
# 				bash -lc "
# 					esearch -db biosample -query '${BIOSAMPLE}' \
# 					| elink -target assembly \
# 					| esummary \
# 					| xtract -pattern DocumentSummary \
# 						-element FtpPath_RefSeq FtpPath_GenBank \
# 					| head -n1
# 				" \
# 			2>/dev/null \
# 			| awk '
# 				{
# 					base = ($1 != "" ? $1 : $2)

# 					if (base != "") {
# 						file = gensub(/.*\//, "", "g", base)
# 						print base "/" file "_genomic.fna.gz"
# 					}
# 				}
# 			'
# 		)

# 		if [[ -z "${URL}" ]]; then
# 			echo "FAILED: ${STRAIN} (${BIOSAMPLE})"
# 			echo -e "${STRAIN}\t${BIOSAMPLE}\t${SPECIES}\t${READDIR}/${BIOSAMPLE}_1.fastq.gz\t${READDIR}/${BIOSAMPLE}_2.fastq.gz\t${OUTDIR}/${STRAIN}.fna.gz" >> "${FAILED}"
	
# 			continue
# 		fi

# 		if ! wget -q -O "${OUTFILE}" "${URL}"; then
# 			echo "FAILED DOWNLOAD: ${STRAIN} (${BIOSAMPLE})"
# 			echo -e "${STRAIN}\t${BIOSAMPLE}\t${SPECIES}\t${READDIR}/${BIOSAMPLE}_1.fastq.gz\t${READDIR}/${BIOSAMPLE}_2.fastq.gz\t${OUTDIR}/${STRAIN}.fna.gz" >> "${FAILED}"
# 			rm -f "${OUTFILE}"
# 			continue
# 		fi

# 		echo "OK: ${STRAIN}"

# 	done
# fi

if [[ "$SKIP_TO_FASTERQ" -eq 0 ]]; then
	mkdir -p "${OUTDIR}"
	: > "${FAILED}"
	printf 'Sample_ID\tBiosample\tSpecies\tR1\tR2\tAssembly\n' > "${FAILED}"
	HEADER=$(head -n1 "${INPUT}")
	printf '%s\tAssembly\n' "$HEADER" > "${OUTPUT_TABLE}"
	STRAIN_COL=$(printf '%s\n' "$HEADER" | tr '\t' '\n' | nl -v1 | awk '$2=="Sample_ID"{print $1}')
	BIOSAMPLE_COL=$(printf '%s\n' "$HEADER" | tr '\t' '\n' | nl -v1 | awk '$2=="Biosample"{print $1}')
	SPECIES_COL=$(printf '%s\n' "$HEADER" | tr '\t' '\n' | nl -v1 | awk '$2=="Species"{print $1}')
	[[ -z "$STRAIN_COL" ]] && { echo "Column 'Sample_ID' not found"; exit 1; }
	[[ -z "$BIOSAMPLE_COL" ]] && { echo "Column 'Biosample' not found"; exit 1; }
	[[ -z "$SPECIES_COL" ]] && { echo "Column 'Species' not found"; exit 1; }
	TMPDIR_DOWNLOAD=$(mktemp -d)
	export INPUT OUTDIR READDIR CONTAINER STRAIN_COL BIOSAMPLE_COL SPECIES_COL TMPDIR_DOWNLOAD
	tail -n +2 "${INPUT}" | awk 'NF {print NR}' | xargs -P "$DOWNLOAD_JOBS" -I{} bash -c '
		INDEX="$1"
		LINE=$(sed -n "$((INDEX+1))p" "$INPUT")
		IFS=$'\''\t'\'' read -r -a FIELDS <<< "$LINE"
		STRAIN="${FIELDS[$((STRAIN_COL-1))]}"
		BIOSAMPLE="${FIELDS[$((BIOSAMPLE_COL-1))]}"
		SPECIES="${FIELDS[$((SPECIES_COL-1))]}"
		[[ -z "$STRAIN" || -z "$BIOSAMPLE" || -z "$SPECIES" ]] && exit 0
		OUTFILE="${OUTDIR}/${STRAIN}.fna.gz"
		if [[ -s "$OUTFILE" ]]; then
			printf "SKIP (exists): %s\n" "$STRAIN"
		else
			printf "Processing: %s (%s)\n" "$STRAIN" "$BIOSAMPLE"
			URL=$(singularity exec </dev/null --env LC_ALL=C,LANG=C,LANGUAGE=C,NCBI_API_KEY="${NCBI_API_KEY:-}" "$CONTAINER" bash -lc "
				esearch -db biosample -query '\''${BIOSAMPLE}'\'' |
				elink -target assembly |
				esummary |
				xtract -pattern DocumentSummary -element FtpPath_RefSeq FtpPath_GenBank |
				head -n1
			" 2>/dev/null | awk '\''{base=($1!=""?$1:$2); if(base!=""){file=base; sub(/^.*\//,"",file); print base "/" file "_genomic.fna.gz"}}'\'')
			if [[ -z "$URL" ]]; then
				printf "FAILED: %s (%s)\n" "$STRAIN" "$BIOSAMPLE"
				printf "%s\t%s\t%s\t%s/%s_1.fastq.gz\t%s/%s_2.fastq.gz\t%s\n" "$STRAIN" "$BIOSAMPLE" "$SPECIES" "$READDIR" "$BIOSAMPLE" "$READDIR" "$BIOSAMPLE" "$OUTFILE" > "$TMPDIR_DOWNLOAD/$INDEX.failed"
			elif wget -q -O "$OUTFILE" "$URL" && [[ -s "$OUTFILE" ]]; then
				printf "OK: %s\n" "$STRAIN"
			else
				printf "FAILED DOWNLOAD: %s (%s)\n" "$STRAIN" "$BIOSAMPLE"
				rm -f "$OUTFILE"
				printf "%s\t%s\t%s\t%s/%s_1.fastq.gz\t%s/%s_2.fastq.gz\t%s\n" "$STRAIN" "$BIOSAMPLE" "$SPECIES" "$READDIR" "$BIOSAMPLE" "$READDIR" "$BIOSAMPLE" "$OUTFILE" > "$TMPDIR_DOWNLOAD/$INDEX.failed"
			fi
		fi
		printf "%s\t%s\n" "$INDEX" "$LINE" > "$TMPDIR_DOWNLOAD/$INDEX.row"
		printf "%s\n" "$OUTFILE" > "$TMPDIR_DOWNLOAD/$INDEX.path"
	' _ {}
	while IFS= read -r INDEX; do
		[[ -s "$TMPDIR_DOWNLOAD/$INDEX.row" ]] || continue
		LINE=$(cut -f2- "$TMPDIR_DOWNLOAD/$INDEX.row")
		OUTFILE=$(cat "$TMPDIR_DOWNLOAD/$INDEX.path")
		printf '%s\t%s\n' "$LINE" "$OUTFILE" >> "$OUTPUT_TABLE"
		[[ -s "$TMPDIR_DOWNLOAD/$INDEX.failed" ]] && cat "$TMPDIR_DOWNLOAD/$INDEX.failed" >> "$FAILED"
	done < <(tail -n +2 "$INPUT" | awk 'NF {print NR}')
	rm -rf "$TMPDIR_DOWNLOAD"
fi

FAILED_SRA="failed_sra_downloads.txt"
: > "$FAILED_SRA"

#Now the failed ones can be checked programmatically or manually, e.g. by looking for the BioSample in the NCBI web interface to see if it has an assembly and if so, what the accession is.
if [[ "$SKIP_TO_FASTERQ" -eq 0 ]]; then
		
	if [[ ! -f "$FAILED" ]]; then
		echo "Failed file not found: $FAILED"
		exit 1
	fi

	if [[ ! -s "$FAILED" ]]; then
		echo "No failed BioSamples. Skipping de novo assembly."
		exit 0
	fi

	mkdir -p "$READDIR"
	READDIR=$(realpath "$READDIR")
	

	tail -n +2 "$FAILED" | awk -F'\t' '{print $2}' | while read -r BIOSAMPLE; do
		[[ -z "$BIOSAMPLE" ]] && continue

		R1="${READDIR}/${BIOSAMPLE}_1.fastq.gz"
		R2="${READDIR}/${BIOSAMPLE}_2.fastq.gz"

		if [[ -s "$R1" && -s "$R2" ]]; then
			echo "SKIP (exists): $BIOSAMPLE"
			continue
		fi

		echo "Processing: $BIOSAMPLE"

		if singularity exec --env NCBI_API_KEY="${NCBI_API_KEY:-}" "$SRA_CONTAINER" \
			fasterq-dump "$BIOSAMPLE" \
			-O "$READDIR" \
			--split-files \
			-e "$THREADS"; then

			pigz -f "$READDIR/${BIOSAMPLE}"_*.fastq || true
		else
			echo "FAILED: $BIOSAMPLE" >&2
			echo "$BIOSAMPLE" >> "$FAILED_SRA"
			continue
		fi
	done

fi

# Now we can create a table for the assembler with the failed BioSamples and their corresponding reads, which can be used to run the assembly pipeline on these samples.



REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSEMBLER_DIR="${REPO_DIR}/denovo_assembler"

if [[ $(wc -l < "$FAILED") -le 1 ]]; then
	echo "No samples available for assembly."
	exit 0
fi

ASSEMBLY_INPUT="$(mktemp)"

head -n 1 "$FAILED" > "$ASSEMBLY_INPUT"

if [[ -s "$FAILED_SRA" ]]; then
	tail -n +2 "$FAILED" \
		| grep -F -v -f "$FAILED_SRA" \
		>> "$ASSEMBLY_INPUT"
else
	tail -n +2 "$FAILED" >> "$ASSEMBLY_INPUT"
fi

if [[ $(wc -l < "$ASSEMBLY_INPUT") -le 1 ]]; then
	echo "No samples remaining for assembly."
	exit 0
fi

snakemake \
	--snakefile "${ASSEMBLER_DIR}/Snakefile" \
	--configfile "${ASSEMBLER_DIR}/config.yaml" \
	--config samples="${ASSEMBLY_INPUT}" assembly_path="${OUTDIR}" \
	-j 40 \
	--profile "${ASSEMBLER_DIR}/profiles/server"


#remove assemblies that failed to download and update the assembly table with the actual paths of the successfully downloaded assemblies


TMP="$(mktemp)"

awk -F'\t' '
BEGIN {
	OFS = FS
}
NR == 1 {
	for (i = 1; i <= NF; i++) {
		if ($i == "Assembly") {
			assembly_col = i
			break
		}
	}

	if (!assembly_col) {
		print "ERROR: Assembly column not found" > "/dev/stderr"
		exit 1
	}

	print
	next
}
{
	if (system("[ -s \"" $assembly_col "\" ]") == 0)
		print
}
' assemblies.tsv > "$TMP"

mv "$TMP" assemblies.tsv