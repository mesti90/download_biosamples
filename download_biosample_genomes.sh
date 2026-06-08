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
	-f  Failed BioSamples file [default: failed_biosamples.txt]
	-c  Singularity container [default: /home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif]
	-t  Output table with assembly paths [default: assemblies.tsv]
	-h  Show this help message
EOF
	exit 1
}

INPUT="biosamples.tsv"
OUTDIR="genomes"
FAILED="failed_biosamples.txt"
CONTAINER="/home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif"

OUTPUT_TABLE="assemblies.tsv"

while getopts ":i:o:f:c:t:h" opt; do
	case "${opt}" in
		i) INPUT="${OPTARG}" ;;
		o) OUTDIR="${OPTARG}" ;;
		f) FAILED="${OPTARG}" ;;
		c) CONTAINER="${OPTARG}" ;;
		t) OUTPUT_TABLE="${OPTARG}" ;;
		h) usage ;;
		*) usage ;;
	esac
done

mkdir -p "${OUTDIR}"
: > "${FAILED}"

HEADER=$(head -n1 "${INPUT}")
echo -e "${HEADER}\tAssembly" > "${OUTPUT_TABLE}"

STRAIN_COL=$(echo "${HEADER}" | tr '\t' '\n' | nl -v1 | awk '$2=="Sample_ID"{print $1}')
BIOSAMPLE_COL=$(echo "${HEADER}" | tr '\t' '\n' | nl -v1 | awk '$2=="Biosample"{print $1}')

[[ -z "${STRAIN_COL}" ]] && { echo "Column 'Sample_ID' not found"; exit 1; }
[[ -z "${BIOSAMPLE_COL}" ]] && { echo "Column 'Biosample' not found"; exit 1; }

tail -n +2 "${INPUT}" | while IFS= read -r LINE; do

	IFS=$'\t' read -r -a FIELDS <<< "${LINE}"

	STRAIN="${FIELDS[$((STRAIN_COL - 1))]}"
	BIOSAMPLE="${FIELDS[$((BIOSAMPLE_COL - 1))]}"

	[[ -z "${STRAIN}" ]] && continue
	[[ -z "${BIOSAMPLE}" ]] && continue

	OUTFILE="${OUTDIR}/${STRAIN}.fna.gz"

	if [[ -s "${OUTFILE}" ]]; then
		echo "SKIP (exists): ${STRAIN}"
		echo -e "${LINE}\t${OUTFILE}" >> "${OUTPUT_TABLE}"
		continue
	fi

	echo "Processing: ${STRAIN} (${BIOSAMPLE})"

	URL=$(
		singularity exec \
			</dev/null \
			--env LC_ALL=C,LANG=C,LANGUAGE=C \
			"${CONTAINER}" \
			bash -lc "
				esearch -db biosample -query '${BIOSAMPLE}' \
				| elink -target assembly \
				| esummary \
				| xtract -pattern DocumentSummary \
					-element FtpPath_RefSeq FtpPath_GenBank \
				| head -n1
			" \
		2>/dev/null \
		| awk '
			{
				base = ($1 != "" ? $1 : $2)

				if (base != "") {
					file = gensub(/.*\//, "", "g", base)
					print base "/" file "_genomic.fna.gz"
				}
			}
		'
	)

	if [[ -z "${URL}" ]]; then
		echo "FAILED: ${STRAIN} (${BIOSAMPLE})"
		echo -e "${STRAIN}\t${BIOSAMPLE}" >> "${FAILED}"
		continue
	fi

	if ! wget -q -O "${OUTFILE}" "${URL}"; then
		echo "FAILED DOWNLOAD: ${STRAIN} (${BIOSAMPLE})"
		echo -e "${STRAIN}\t${BIOSAMPLE}" >> "${FAILED}"
		rm -f "${OUTFILE}"
		continue
	fi

	echo "OK: ${STRAIN}"
	echo -e "${LINE}\t${OUTFILE}" >> "${OUTPUT_TABLE}"

done