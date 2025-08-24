#!/usr/bin/env Rscript

# Packages
suppressPackageStartupMessages({
  library(jsonlite)
  library(httr)
  library(utils)
})

GITHUB_TOKEN <- Sys.getenv("GITHUB_TOKEN")
if (GITHUB_TOKEN == "") {
  message("NOTE: GITHUB_TOKEN not set. You will be rate-limited (60/hr).")
}
gh_headers <- function() {
  h <- c("Accept" = "application/vnd.github+json", "X-GitHub-Api-Version" = "2022-11-28")
  if (GITHUB_TOKEN != "") h <- c(h, Authorization = paste("Bearer", GITHUB_TOKEN))
  h
}

safe_get <- function(url) {
  resp <- httr::GET(url, httr::add_headers(.headers = gh_headers()), httr::user_agent("masud90-portfolio-builder"))
  list(status = httr::status_code(resp), content = httr::content(resp, as = "text", encoding = "UTF-8"))
}

# Read CSV
projects_path <- "_data/projects.csv"
if (!file.exists(projects_path)) stop("Missing _data/projects.csv")
df <- read.csv(projects_path, stringsAsFactors = FALSE)

meta <- list()

for (i in seq_len(nrow(df))) {
  row <- df[i,]
  id <- row$id
  owner <- row$repo_owner
  repo  <- row$repo_name

  message(sprintf("Processing %s/%s (%s)", owner, repo, id))

  # 1) Latest release
  release_date <- NA
  url_rel <- sprintf("https://api.github.com/repos/%s/%s/releases/latest", owner, repo)
  r_rel <- safe_get(url_rel)
  if (r_rel$status == 200) {
    j <- jsonlite::fromJSON(r_rel$content)
    release_date <- j$published_at
  }

  # 2) Fallback: latest commit
  commit_date <- NA
  if (is.na(release_date)) {
    url_comm <- sprintf("https://api.github.com/repos/%s/%s/commits?per_page=1", owner, repo)
    r_comm <- safe_get(url_comm)
    if (r_comm$status == 200) {
      j <- jsonlite::fromJSON(r_comm$content)
      if (length(j) >= 1) {
        commit_date <- j$commit$author$date[[1]]
      }
    }
  }

  # 3) README (raw)
  readme_md <- NULL
  url_readme <- sprintf("https://api.github.com/repos/%s/%s/readme", owner, repo)
  r_rm <- safe_get(url_readme)
  if (r_rm$status == 200) {
    j <- jsonlite::fromJSON(r_rm$content)
    download_url <- j$download_url
    if (!is.null(download_url) && nzchar(download_url)) {
      r_raw <- httr::GET(download_url, httr::user_agent("masud90-portfolio-builder"))
      if (httr::status_code(r_raw) == 200) {
        readme_md <- httr::content(r_raw, as = "text", encoding = "UTF-8")
      }
    }
  }

  # 4) Write per-project page with README body
  dir.create(file.path("projects", id), showWarnings = FALSE, recursive = TRUE)
  front <- c(
    "---",
    "layout: project",
    paste0("title: \"", row$title, "\""),
    paste0("repo_url: \"", row$repo_url, "\""),
    "section: \"Open-Source\"",
    "---",
    ""
  )
  body <- if (!is.null(readme_md)) readme_md else "README not available yet."
  writeLines(c(front, body), con = file.path("projects", id, "index.md"))

  # 5) Build meta record
  meta[[length(meta) + 1]] <- list(
    id = id,
    last_release_date = if (!is.na(release_date)) release_date else NULL,
    latest_commit_date = if (!is.na(commit_date)) commit_date else NULL
  )
}

# 6) Write meta JSON for Jekyll data
dir.create("_data", showWarnings = FALSE)
writeLines(jsonlite::toJSON(meta, auto_unbox = TRUE, pretty = TRUE), "_data/projects_meta.json")

message("Done. Wrote _data/projects_meta.json and project pages.")
