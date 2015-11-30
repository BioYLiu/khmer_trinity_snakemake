shell.prefix("set -euo pipefail;")

configfile: "config.yaml.example"

# List variables
ENDS = "1 2 u".split()
PAIRS = "pe_pe pe_se".split()
SAMPLES_PE  = config["samples_pe"]
SAMPLES_SE  = config["samples_se"]


# Folder variables
RAW_DIR         = "data/fastq_raw"
TRIM_DIR        = "data/fastq_trimmed"
NORM_DIR        = "data/fastq_norm"
ASSEMBLY_DIR    = "data/assembly"
FASTQC_RAW_DIR  = "data/fastqc_raw"
FASTQC_TRIM_DIR = "data/fastqc_trimmed"
FASTQC_NORM_DIR = "data/fastqc_norm"

# Path to programs (or element on path)

trinity     = config["software"]["trinity"]
trimmomatic = config["software"]["trimmomatic"]
gzip        = config["software"]["gzip"]

rule all:
    input:
        ASSEMBLY_DIR + "/Trinity.fasta",
        expand( # fastqc zip and html files for PE data DIGINORM
            FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data DIGINORM
            FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for PE data QC
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data QC
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        )



rule clean:
    shell:
        """
        rm -rf data/fastq_trimmed
        rm -rf data/fastqc_trimmed
        rm -rf data/fastq_norm
        rm -rf data/fastqc_norm
        rm -rf data/assembly
        rm -rf logs
        rm -rf benchmarks
        """



####
# Quality control rules
####

rule qc_trimmomatic_pe:
    """
    Run trimmomatic on paired end mode to eliminate Illumina adaptors and remove
        low quality regions and reads.
    Inputs _1 and _2 are piped through gzip/pigz.
    Outputs _1 and _2 are piped to gzip/pigz (level 9).
    Outputs _3 and _4 are compressed with the builtin compressor from 
        Trimmomatic. Further on they are catted and compressed with gzip/pigz 
        (level 9).
    Note: The cut -f 1 -d " " is to remove additional fields in the FASTQ header. It is done posterior to the trimming since the output comes slower than the input is read.
    """
    input:
        forward = lambda wildcards: config["samples_pe"][wildcards.sample]["forward"],
        reverse = lambda wildcards: config["samples_pe"][wildcards.sample]["reverse"]
    output:
        forward     = temp(TRIM_DIR + "/{sample}_1.fq.gz"),
        reverse     = temp(TRIM_DIR + "/{sample}_2.fq.gz"),
        unpaired    = protected(TRIM_DIR + "/{sample}.final.pe_se.fq.gz")
    params:
        unpaired_1  = TRIM_DIR + "/{sample}_3.fq.gz",
        unpaired_2  = TRIM_DIR + "/{sample}_4.fq.gz",
        adaptor     = lambda wildcards: config["samples_pe"][wildcards.sample]["adaptor"],
        phred       = lambda wildcards: config["samples_pe"][wildcards.sample]["phred"],
        trimmomatic_params = config["trimmomatic_params"]
    benchmark:
        "benchmarks/qc/trimmomatic_pe_{sample}.json"
    log:
        "logs/qc/trimmomatic_pe_{sample}.log" 
    threads:
        4 # It doesn't perform well above this value
    shell:
        """
        {trimmomatic} PE \
            -threads {threads} \
            -{params.phred} \
            <({gzip} -dc {input.forward} ) \
            <({gzip} -dc {input.reverse} ) \
            >(cut -f 1 -d " " | {gzip} -9 > {output.forward} ) \
            {params.unpaired_1} \
            >(cut -f 1 -d " " | {gzip} -9 > {output.reverse} ) \
            {params.unpaired_2} \
            ILLUMINACLIP:{params.adaptor}:2:30:10 \
            {params.trimmomatic_params} \
            2> {log}
            
        zcat {params.unpaired_1} {params.unpaired_2} |
        cut -f 1 -d " " |
        {gzip} -9 > {output.unpaired}
        
        rm {params.unpaired_1} {params.unpaired_2}
        """



rule qc_trimmomatic_se:
    """
    Run trimmomatic on single end mode to eliminate Illumina adaptors and 
        remove low quality regions and reads.
    Input is piped through gzip/pigz.
    Output is piped to gzip.
    """
    input:
        single = lambda wildcards: config["samples_se"][wildcards.sample]["single"],
    output:
        single     = protected(TRIM_DIR + "/{sample}.final.se.fq.gz")
    params:
        adaptor     = lambda wildcards: config["samples_se"][wildcards.sample]["adaptor"],
        phred       = lambda wildcards: config["samples_se"][wildcards.sample]["phred"],
        trimmomatic_params = config["trimmomatic_params"]
    benchmark:
        "benchmarks/qc/trimmomatic_se_{sample}.json"
    log:
        "logs/qc/trimmomatic_se_{sample}.log" 
    threads:
        4 # It doesn't perform well above this value
    shell:
        """
        {trimmomatic} SE \
            -threads {threads} \
            -{params.phred} \
            <({gzip} -dc {input.single}) \
            >(cut -f 1 -d " " | {gzip} -9 > {output.single}) \
            ILLUMINACLIP:{params.adaptor}:2:30:10 \
            {params.trimmomatic_params} \
            2> {log}
        """
    

rule qc_interleave_pe_pe:
    """
    From the adaptor free _1 and _2 , interleave the reads.
    Read the inputs, interleave, filter the stream and compress.
    """
    input:
        forward= TRIM_DIR + "/{sample}_1.fq.gz",
        reverse= TRIM_DIR + "/{sample}_2.fq.gz"
    output:
        interleaved= protected(TRIM_DIR + "/{sample}.final.pe_pe.fq.gz")
    threads:
        2
    log:
        "logs/qc/interleave_pe_{sample}.log"
    benchmark:
        "benchmarks/qc/interleave_pe_{sample}.json"
    shell:
        """
        ( python bin/interleave-reads.py \
            {input.forward} \
            {input.reverse} |
        {gzip} -9 > {output.interleaved} ) \
        2> {log}
        """



rule qc_fastqc:
    """
    Do FASTQC reports
    Uses --nogroup!
    One thread per fastq.gz file
    """
    input:
        fastq = TRIM_DIR + "/{sample}.final.{pair}.fq.gz"
    output:
        zip   = FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.zip",
        html  = FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.html" 
    threads:
        1
    params:
        zip   = TRIM_DIR + "/{sample}.final.{pair}_fastqc.zip",
        html  = TRIM_DIR + "/{sample}.final.{pair}_fastqc.html"
    log:
        "logs/qc/fastqc_trimmed_{sample}_{pair}.log"
    benchmark:
        "benchmarks/qc/fastqc_trimmed_{sample}_{pair}.json"
    shell:
        """
        fastqc \
            --nogroup \
            {input.fastq} \
        > {log} 2>&1
        
        mv {params.zip} {output.zip}
        mv {params.html} {output.html}
        """


rule qc:
    """
    Rule to do all the Quality Control:
        - qc_trimmomatic_pe
        - qc_trimmomatic_se
        - qc_interleave_pe_pe
    """
    input:
        expand( # fq.gz files for PE data
            TRIM_DIR + "/{sample}.final.{pair}.fq.gz",
            sample = SAMPLES_PE,
            pair   = PAIRS
        ),
        expand( # fq.gz files for SE data
            TRIM_DIR + "/{sample}.final.{pair}.fq.gz",
            sample = SAMPLES_SE,
            pair = ["se"]
        ),
        expand( # fastqc zip and html files for PE data
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        )




rule diginorm_load_into_counting:
    """
    Build the hash table data structure from all the trimmed reads.
    """
    input:
        fastqs = expand(
            TRIM_DIR + "/{sample}.final.{pair}.fq.gz",
            sample = SAMPLES_PE,
            pair = PAIRS
        ) + expand(
            TRIM_DIR + "/{sample}.final.se.fq.gz",
            sample = SAMPLES_SE
        )
    output:
        table = temp(NORM_DIR + "/diginorm_table.kh"),
        info  = temp(NORM_DIR + "/diginorm_table.kh.info")
    threads:
        24
    log:
        "logs/diginorm/load_into_counting.log"
    benchmark:
        "benchmarks/diginorm/load_into_counting.json"
    params:
        ksize=         config["diginorm_params"]["ksize"],
        max_tablesize= config["diginorm_params"]["max_tablesize"],
        n_tables=      config["diginorm_params"]["n_tables"]
    shell:
        """
        ./bin/load-into-counting.py \
            --ksize {params.ksize} \
            --n_tables {params.n_tables} \
            --max-tablesize {params.max_tablesize} \
            --threads {threads} \
            --no-bigcount \
            {output.table} \
            {input.fastqs} \
        2>  {log}
        """



rule diginorm_normalize_by_median_pe_pe:
    """
    Normalizes by median EACH FILE.
    Therefore one loads once per file the hash table.
    """
    input:
        fastq = TRIM_DIR + "/{sample}.final.pe_pe.fq.gz",
        table = NORM_DIR + "/diginorm_table.kh"
    output:
        fastq = temp(NORM_DIR + "/{sample}.keep.pe_pe.fq.gz")
    threads:
        24 # Block RAM
    params:
        cutoff = config["diginorm_params"]["cutoff"]
    log:
        "logs/diginorm/normalize_by_median_pe_pe_{sample}.log"
    benchmark:
        "benchmarks/diginorm/normalize_by_median_pe_pe_{sample}.json"
    shell:
        """
        ( ./bin/normalize-by-median.py \
            --paired \
            --loadgraph {input.table} \
            --cutoff {params.cutoff} \
            --output - \
            {input.fastq} |
        pigz -9 \
        > {output.fastq} ) \
        2> {log}
        """



rule diginorm_normalize_by_median_pe_se:
    """
    Normalizes by median EACH FILE.
    Therefore one loads once per file the hash table.
    """
    input:
        fastq = TRIM_DIR + "/{sample}.final.pe_se.fq.gz",
        table = NORM_DIR + "/diginorm_table.kh"
    output:
        fastq = temp(NORM_DIR + "/{sample}.keep.pe_se.fq.gz")
    threads:
        24 # Block excessive RAM usage
    params:
        cutoff = config["diginorm_params"]["cutoff"]
    log:
        "logs/diginorm/normalize_by_median_pe_se_{sample}.log"
    benchmark:
        "benchmarks/diginorm/normalize_by_median_pe_se_{sample}.json"
    shell:
        """
        ( ./bin/normalize-by-median.py \
            --loadgraph {input.table} \
            --cutoff {params.cutoff} \
            --output - \
            {input.fastq} |
        {gzip} -9 \
        > {output.fastq} ) \
        2> {log}
        """



rule diginorm_normalize_by_median_se:
    """
    Normalizes by median EACH FILE.
    Therefore one loads once per file the hash table.
    """
    input:
        fastq = TRIM_DIR + "/{sample}.final.se.fq.gz",
        table = NORM_DIR + "/diginorm_table.kh"
    output:
        fastq = temp(NORM_DIR + "/{sample}.keep.se.fq.gz")
    threads:
        24 # Block excessive RAM usage
    params:
        cutoff = config["diginorm_params"]["cutoff"]
    log:
        "logs/diginorm/normalize_by_median_se_{sample}.log"
    benchmark:
        "benchmarks/diginorm/normalize_by_median_se_{sample}.json"
    shell:
        """
        ( ./bin/normalize-by-median.py \
            --loadgraph {input.table} \
            --cutoff {params.cutoff} \
            --output - \
            {input.fastq} |
        {gzip} -9 \
        > {output.fastq} ) \
        2> {log}
        """



rule diginorm_filter_abund:
    """
    Removes erroneus k-mers.
    """
    input:
        fastq = NORM_DIR + "/{sample}.keep.{pair}.fq.gz",
        table = NORM_DIR + "/diginorm_table.kh"
    output:
        fastq = temp(NORM_DIR + "/{sample}.abundfilt.{pair}.fq.gz")
    threads:
        24
    params:
        ""
    log:
        "logs/diginorm/filter_abund_{sample}_{pair}.log"
    benchmark:
        "benchmarks/diginorm_filter_abunt_{sample}_{pair}.json"
    shell:
        """
        ( ./bin/filter-abund.py \
            --variable-coverage \
            --threads {threads} \
            --output - \
            {input.table} \
            {input.fastq} |
        {gzip} -9 \
        > {output.fastq} ) \
        2> {log}
        """



rule diginorm_extract_paired_reads:
    input:
        fastq = NORM_DIR + "/{sample}.abundfilt.pe_pe.fq.gz"
    output:
        fastq_pe = protected(NORM_DIR + "/{sample}.final.pe_pe.fq.gz"),
        fastq_se = temp(NORM_DIR + "/{sample}.temp.pe_se.fq.gz")
    threads:
        1
    log:
        "logs/diginorm/extract_paired_reads_{sample}.log"
    benchmark:
        "benchmarks/diginorm/extract_paired_reads_{sample}.json"
    shell:
        """
        ./bin/extract-paired-reads.py \
            --output-paired {output.fastq_pe} \
            --output-single {output.fastq_se} \
            --gzip \
            {input.fastq} \
        2> {log}
        """



rule diginorm_merge_pe_single_reads:
    input:
        from_norm=   NORM_DIR + "/{sample}.abundfilt.pe_se.fq.gz",
        from_paired= NORM_DIR + "/{sample}.temp.pe_se.fq.gz"
    output:
        fastq = protected(NORM_DIR + "/{sample}.final.pe_se.fq.gz")
    threads:
        1
    log:
        "logs/diginorm/merge_single_reads_{sample}.log"
    benchmark:
        "benchmarks/diginorm/merge_single_reads_{sample}.json"
    shell:
        """
        cp {input.from_norm} {output.fastq}
        {gzip} -dc {input.from_paired} |
        {gzip} -9 >> {output.fastq} 
        """



rule dignorm_get_former_se_reads:
    """
    Move the result of diginorm_extract_paired_reads for true SE reads to their
    final position.
    """
    input:
        single= NORM_DIR + "/{sample}.abundfilt.se.fq.gz"
    output:
        single= NORM_DIR + "/{sample}.final.se.fq.gz"
    threads:
        1
    log:
        "logs/diginorm/get_former_se_reads_{sample}.log"
    benchmark:
        "benchmarks/diginorm/get_former_se_reads_{sample}.json"
    shell:
        """
        mv {input.single} {output.single}
        """



rule diginorm_fastqc:
    """
    Do FASTQC reports
    Uses --nogroup!
    One thread per fastq.gz file
    """
    input:
        fastq = NORM_DIR + "/{sample}.final.{pair}.fq.gz"
    output:
        zip   = FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.zip",
        html  = FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.html" 
    threads:
        1
    params:
        zip   = NORM_DIR + "/{sample}.final.{pair}_fastqc.zip",
        html  = NORM_DIR + "/{sample}.final.{pair}_fastqc.html"
    log:
        "logs/diginorm/fastqc_trimmed_{sample}_{pair}.log"
    benchmark:
        "benchmarks/diginorm/fastqc_trimmed_{sample}_{pair}.json"
    shell:
        """
        fastqc \
            --nogroup \
            {input.fastq} \
        > {log} 2>&1
        
        mv {params.zip} {output.zip}
        mv {params.html} {output.html}
        """


rule diginorm:
    """
    Rule to do the Quality Control and the Digital Normalization:
    qc:
        - qc_trimmomatic_pe
        - qc_trimmomatic_se
        - qc_interleave_pe_pe
    Diginorm:
        - diginorm_load_into_counting
        - diginorm_normalize_by_median_pe_pe
        - diginorm_normalize_by_median_pe_se
        - diginorm_filter_abund
        - diginorm_extract_paired_reads
        - diginorm_merge_pe_single_reads
        - diginorm_get_former_se_reads
    """
    input:
        expand( # pe_pe
            NORM_DIR + "/{sample}.final.pe_pe.fq.gz",
            sample = SAMPLES_PE
        ),
        expand( # pe_se
            NORM_DIR + "/{sample}.final.pe_se.fq.gz",
            sample = SAMPLES_PE
        ) + expand( # se
            NORM_DIR + "/{sample}.final.se.fq.gz",
            sample = SAMPLES_SE
        ),
        expand( # fastqc zip and html files for PE data DIGINORM
            FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data DIGINORM
            FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for PE data QC
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data QC
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        )
        
        



rule assembly_prepare_reads:
    """
    Split PE reads into left and right.fq
    Append SE reads to left.fq
    """
    input:
        pe = expand(
            NORM_DIR + "/{sample}.final.pe_pe.fq.gz",
            sample = SAMPLES_PE
        ),
        se = expand(
            NORM_DIR + "/{sample}.final.pe_se.fq.gz",
            sample = SAMPLES_PE
        ) + expand(
            NORM_DIR + "/{sample}.final.se.fq.gz",
            sample = SAMPLES_SE
        )
    output:
        left  = temp(ASSEMBLY_DIR + "/left.fq"),
        right = temp(ASSEMBLY_DIR + "/right.fq")
    threads:
        1
    params:
        orphans = ASSEMBLY_DIR + "/orphans.fq"
    log:
        "logs/assembly/prepare_reads.log"
    benchmark:
        "benchmarks/assembly/prepare_reads.json"
    shell:
        """
        ./bin/split-paired-reads.py \
            --output-orphaned {params.orphans} \
            --output-first {output.left} \
            --output-second {output.right} \
            <({gzip} -dc {input.pe}) \
        > {log} 2>&1
        
        {gzip} -dc {input.se} >> {output.left}
        
        cat {params.orphans} >> {output.left}
        rm {params.orphans}
        """



rule assembly_run_trinity:
    """
    Assembly reads with Trinity.
    Notes on hardcoded settings:
        - Runs on paired end mode
        - Expect fastq files as inputs (left and right)
        - Does the full cleanup so it only remains a fasta file.
    """
    input:
        left  = ASSEMBLY_DIR + "/left.fq",
        right = ASSEMBLY_DIR + "/right.fq"
    output:
        fasta = protected(ASSEMBLY_DIR + "/Trinity.fasta")
    threads:
        24
    params:
        memory= config["trinity_params"]["memory"],
        outdir= ASSEMBLY_DIR + "/trinity_out_dir"
    log:
        "logs/assembly/run_trinity.log"
    benchmark:
        "benchmarks/assembly/run_trinity.log"
    shell:
        """
        ./bin/Trinity \
            --seqType fq \
            --max_memory {params.memory} \
            --left {input.left} \
            --right {input.right} \
            --CPU {threads} \
            --full_cleanup \
            --output {params.outdir} \
        > {log}
        
        mv {params.outdir}.Trinity.fasta {output.fasta}
        """



rule assembly:
    """
    Runs from raw data to assembly:
    QC:
        - qc_trimmomatic_pe
        - QC_interleave_pe
        
    Diginorm:
        - diginorm_load_into_counting
        - diginorm_normalize_by_median_pe
        - diginorm_normalize_by_median_se
        - diginorm_filter_abund
        - diginorm_extract_paired_reads
        - diginorm_merge_single_reads
    Assembly:
        - assembly_prepare_reads
        - assembly_run_trinity
    """
    input:
        ASSEMBLY_DIR + "/Trinity.fasta",
        expand( # fastqc zip and html files for PE data DIGINORM
            FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data DIGINORM
            FASTQC_NORM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for PE data QC
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_PE,
            pair   = PAIRS,
            extension = "zip html".split()
        ),
        expand( # fastqc zip and html files for SE data QC
            FASTQC_TRIM_DIR + "/{sample}.final.{pair}_fastqc.{extension}",
            sample = SAMPLES_SE,
            pair = ["se"],
            extension = "zip html".split()
        )
        
