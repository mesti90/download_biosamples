#!/usr/bin/env python3

import argparse
import subprocess
from pathlib import Path
import pandas as pd


# -----------------------------
# utils
# -----------------------------

def run(cmd):
	print(" ".join(map(str, cmd)))
	subprocess.run(cmd, check=True)


def ensure_dir(p):
	Path(p).mkdir(parents=True, exist_ok=True)


# -----------------------------
# NCBI lookup
# -----------------------------

def get_ncbi_assembly(biosample, container):
	cmd = f"""
	esearch -db biosample -query '{biosample}' \
	| elink -target assembly \
	| esummary \
	| xtract -pattern DocumentSummary -element FtpPath_RefSeq FtpPath_GenBank
	"""

	out = subprocess.check_output(
		["singularity", "exec", container, "bash", "-lc", cmd],
		text=True
	).strip()

	if not out:
		return None

	parts = out.split()
	base = parts[0] if parts[0] else parts[1]

	if not base:
		return None

	name = base.split("/")[-1]
	return f"{base}/{name}_genomic.fna.gz"


# -----------------------------
# stage 1: NCBI assemblies
# -----------------------------

def stage_ncbi(df, args):
	ensure_dir(args.outdir)

	failed = []
	rows = []

	for _, r in df.iterrows():
		sample = r["Sample_ID"]
		biosample = r["Biosample"]

		outfile = Path(args.outdir) / f"{sample}.fna.gz"

		if args.skip_assembly_download:
			rows.append((sample, biosample, str(outfile) if outfile.exists() else ""))
			continue

		if outfile.exists():
			rows.append((sample, biosample, str(outfile)))
			continue

		url = get_ncbi_assembly(biosample, args.container)

		if not url:
			failed.append(biosample)
			rows.append((sample, biosample, ""))
			continue

		try:
			run(["wget", "-q", "-O", str(outfile), url])
			rows.append((sample, biosample, str(outfile)))
		except subprocess.CalledProcessError:
			failed.append(biosample)
			rows.append((sample, biosample, ""))

	return pd.DataFrame(rows, columns=["Sample_ID", "Biosample", "Assembly"]), failed


# -----------------------------
# stage 2: reads
# -----------------------------

def stage_reads(df, failed, args):
	read_dir = Path(args.readdir)
	ensure_dir(read_dir)

	if args.skip_read_download:
		return read_dir

	for biosample in failed:
		run([
			"singularity", "exec", args.sra_container,
			"fasterq-dump", biosample,
			"-O", str(read_dir),
			"--split-files",
			"-e", str(args.threads)
		])

		run(["pigz", "-f", str(read_dir / f"{biosample}_*.fastq")])

	return read_dir


# -----------------------------
# stage 3: denovo table
# -----------------------------

def stage_denovo(df, failed, read_dir, args):
	if args.skip_denovo:
		return None

	failed_set = set(failed)
	rows = []

	for _, r in df.iterrows():
		if r["Biosample"] not in failed_set:
			continue

		r1 = read_dir / f"{r['Biosample']}_1.fastq.gz"
		r2 = read_dir / f"{r['Biosample']}_2.fastq.gz"

		if not (r1.exists() and r2.exists()):
			continue

		rows.append({
			"Sample_ID": r["Sample_ID"],
			"Species": r.get("Species", ""),
			"R1": str(r1),
			"R2": str(r2),
			"Assembly": ""
		})

	if not rows:
		return None

	outfile = read_dir / "denovo_assembler_samples.tsv"
	pd.DataFrame(rows).to_csv(outfile, sep="\t", index=False)

	run([
		"snakemake",
		"--snakefile", str(Path(__file__).parent / "denovo_assembler/Snakefile"),
		"--configfile", str(Path(__file__).parent / "denovo_assembler/config.yaml"),
		"--config", f"samples={outfile}",
		"-j", str(args.threads),
		"--profile", str(Path(__file__).parent / "denovo_assembler/profiles/server")
	])

	return outfile


# -----------------------------
# stage 4: merge final table
# -----------------------------

def build_final(df_ncbi, denovo_table, output):
	df = df_ncbi.copy()

	if denovo_table and Path(denovo_table).exists():
		dn = pd.read_csv(denovo_table, sep="\t")
		dn = dn[dn["Assembly"].notna() & (dn["Assembly"] != "")]
		dn = dn[["Sample_ID", "Assembly"]]

		df = df.merge(dn, on="Sample_ID", how="left", suffixes=("", "_denovo"))
		df["Assembly"] = df["Assembly"].fillna(df["Assembly_denovo"])
		df.drop(columns=["Assembly_denovo"], inplace=True)

	df.to_csv(output, sep="\t", index=False)


# -----------------------------
# main
# -----------------------------

def main():
	ap = argparse.ArgumentParser( description="Download genomes from NCBI, fallback to SRA + de novo assembly, and produce a unified assembly table." )
	ap.add_argument( "-i", default="biosamples.tsv", help="Input TSV file with at least columns: Sample_ID, Biosample (optionally Species)." )

	ap.add_argument( "-o", "--outdir",default="genomes", help="Output directory for downloaded NCBI assemblies (default: genomes).")

	ap.add_argument( "-r", default="sra_reads", help="Output directory for SRA reads downloaded via fasterq-dump (default: sra_reads)." )

	ap.add_argument( "-t", default="assemblies.tsv", help="Final output TSV containing Sample_ID, Biosample, Species, and Assembly path (default: assemblies.tsv)." )

	ap.add_argument( "-c", default="/home/vasarhelyib/containers/mesti90-ncbi_edirect.24.7.20250903.sif", help="Singularity container containing NCBI EDirect tools (esearch/elink/esummary/xtract).")
				

	ap.add_argument("-d", default="/home/vasarhelyib/containers/ncbi-sra-tools.3.4.1.sif", help="Singularity container containing SRA-tools (fasterq-dump, etc.).")

	ap.add_argument( "--threads", type=int, default=8, help="Number of threads used for fasterq-dump and downstream processing (default: 8).")

	ap.add_argument("--skip-assembly-download", action="store_true")
	ap.add_argument("--skip-read-download", action="store_true")
	ap.add_argument("--skip-denovo", action="store_true")

	args = ap.parse_args()

	df = pd.read_csv(args.i, sep="\t")

	df_ncbi, failed = stage_ncbi(df, args)
	read_dir = stage_reads(df, failed, args)
	denovo_table = stage_denovo(df, failed, read_dir, args)

	build_final(df_ncbi, denovo_table, args.t)


if __name__ == "__main__":
	main()