# Download Assemblies from NCBI BioSamples

Download genome assemblies from NCBI using BioSample accessions and generate an updated sample sheet containing assembly paths.

## Overview

This script:

1. Reads a TSV file containing sample metadata.
2. Retrieves the associated assembly for each BioSample from NCBI.
3. Downloads the assembly FASTA (`*.fna.gz`).
4. Stores assemblies as:

```
<output_directory>/<Sample_ID>.fna.gz
```

5. Produces an output TSV containing all original columns plus an additional `Assembly` column with the relative path to the downloaded genome.

Assemblies that already exist are skipped automatically.

---

## Requirements

* Bash ≥ 4
* Singularity / Apptainer
* NCBI EDirect installed inside the container
* `wget`
* `awk`

Default container:

```
/home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif
```

---

## Input Format

Input must be a tab-separated file containing at least the following columns:

| Column    | Description              |
| --------- | ------------------------ |
| Sample_ID | Unique sample identifier |
| Biosample | NCBI BioSample accession |

Example:

```tsv
Sample_ID	Biosample	Country
KP001	SAMN12345678	Hungary
KP002	SAMN87654321	France
```

Additional columns are preserved in the output table.

---

## Usage

```bash
download_biosamples.sh \
	-i samples.tsv \
	-o genomes \
	-t assemblies.tsv
```

### Options

| Option | Description                          |
| ------ | ------------------------------------ |
| `-i`   | Input TSV file                       |
| `-o`   | Output directory for assemblies      |
| `-t`   | Output TSV containing assembly paths |
| `-f`   | File containing failed downloads     |
| `-c`   | Singularity container                |
| `-h`   | Show help message                    |

Defaults:

```text
Input TSV:          biosamples.tsv
Output directory:   genomes
Output table:       assemblies.tsv
Failed file:        failed_biosamples.txt
Container:          /home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif
```

---

## Output

### Downloaded assemblies

```text
genomes/
├── KP001.fna.gz
├── KP002.fna.gz
└── KP003.fna.gz
```

### Updated sample sheet

Input:

```tsv
Sample_ID	Biosample	Country
KP001	SAMN12345678	Hungary
KP002	SAMN87654321	France
```

Output:

```tsv
Sample_ID	Biosample	Country	Assembly
KP001	SAMN12345678	Hungary	genomes/KP001.fna.gz
KP002	SAMN87654321	France	genomes/KP002.fna.gz
```

---

## Failed Downloads

BioSamples for which no assembly could be found or downloaded are written to:

```text
failed_biosamples.txt
```

Example:

```text
KP003	SAMN99999999
KP004	SAMN88888888
```

---

## Notes

* RefSeq assemblies are preferred when available.
* If no RefSeq assembly exists, the corresponding GenBank assembly is used.
* Existing non-empty assembly files are not downloaded again.
* The output TSV includes both newly downloaded and previously existing assemblies.
* Paths in the `Assembly` column are stored as relative paths, making the output suitable for downstream Snakemake workflows.

---

## Example Snakemake Integration

```python
rule download_assemblies:
	input:
		"samples.tsv"
	output:
		table="assemblies.tsv",
		failed="failed_biosamples.txt"
	params:
		outdir="genomes"
	shell:
		"""
		download_biosamples.sh \
			-i {input} \
			-o {params.outdir} \
			-t {output.table} \
			-f {output.failed}
		"""
```
