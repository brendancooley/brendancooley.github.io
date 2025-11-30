# Justfile for building Zola site with R Markdown posts
# Usage: just <command>

# Default recipe that lists available commands
default:
    @just --list

# Render R Markdown files to Markdown for Zola
render-posts:
    @echo "Rendering R Markdown files..."
    @mkdir -p content/posts
    @Rscript scripts/render_post.R "src/posts/dists.Rmd" "content/posts/dists.md"
    @Rscript scripts/render_post.R "src/posts/icews.Rmd" "content/posts/icews.md"
    @echo "R Markdown posts rendered successfully!"

# Build the Zola site
build: render-posts
    @echo "Building Zola site..."
    zola build
    @echo "Site built in docs/ directory"

# Serve the site for development
serve: render-posts
    @echo "Starting development server..."
    zola serve

# Clean generated files
clean:
    @echo "Cleaning generated files..."
    @rm -f content/posts/dists.md content/posts/icews.md
    @rm -f static/posts/capital-cities-map.png
    @rm -rf content/posts/*_files/
    @rm -rf docs/*
    @echo "Cleaned up generated files"

# Full rebuild (clean + build)
rebuild: clean build
    @echo "Full rebuild complete!"

# Install R dependencies (run once)
install-r-deps:
    @echo "Installing R dependencies..."
    @Rscript -e "options(repos = c(CRAN = 'https://cran.rstudio.com/')); packages <- c('rmarkdown', 'knitr', 'readr', 'dplyr', 'tidyr', 'ggplot2'); install.packages(packages[!packages %in% installed.packages()]);"
    @echo "R dependencies installed!"

# Check if required tools are available
check:
    @echo "Checking dependencies..."
    @command -v zola >/dev/null 2>&1 || { echo "Error: zola not found. Please install zola."; exit 1; }
    @command -v Rscript >/dev/null 2>&1 || { echo "Error: R not found. Please install R."; exit 1; }
    @Rscript -e "stopifnot(require(rmarkdown))" 2>/dev/null || { echo "Error: rmarkdown package not found. Run 'just install-r-deps'."; exit 1; }
    @echo "All dependencies are available!"