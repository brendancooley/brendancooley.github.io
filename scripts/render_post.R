#!/usr/bin/env Rscript

# Script to render a single R Markdown file to Zola-compatible Markdown
# Usage: Rscript render_post.R <input.Rmd> <output.md>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("Usage: Rscript render_post.R <input.Rmd> <output.md>")
}

input_file <- args[1]
output_file <- args[2]

# Ensure output directory exists
output_dir <- dirname(output_file)
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Render the R Markdown file
rmarkdown::render(
  input = input_file,
  output_format = rmarkdown::md_document(
    variant = 'gfm',
    preserve_yaml = TRUE,
    pandoc_args = c('--wrap=none')
  ),
  output_file = basename(output_file),
  output_dir = output_dir,
  quiet = FALSE
)

cat("Successfully rendered:", input_file, "->", output_file, "\n")