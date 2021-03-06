add_equations_impl <- function(data, dbh_unit) {
  data$dbh <- convert_units(
    data$dbh, from = dbh_unit, to = "mm", quietly = TRUE
  )

  ui_done("Matching equations by site and species.")
  eqn <- suppressMessages(fgeo.biomass::default_eqn(allodb::master_tidy()))
  eqn_from_here <- replace_site(
    eqn, from = "any-temperate-north america", to = unique(data$site)
  )
  .by <- c("species", "site")
  # .by <- c("sp", "site")
  matched <- left_join(data, eqn_from_here, by = .by)

  ui_done("Refining equations according to {ui_field('dbh')}.")
  matched$dbh_in_range <- is_in_range(
    matched$dbh, min = matched$dbh_min_mm, max = matched$dbh_max_mm
  )
  in_range <- filter(matched, .data$dbh_in_range)
  refined <- suppressMessages(left_join(data, in_range))
  refined$dbh_in_range <- NULL

  ui_done("Using generic equations where expert equations can't be found.")
  out <- prefer_expert_equations(refined)

  warn_if_species_missmatch(out, eqn_from_here)
  warn_if_missing_equations(out)

  out
}
add_equations_memoised <- memoise::memoise(add_equations_impl)

#' Find allometric equations in allodb or in a custom equations-table.
#'
#' @param data A dataframe as those created with [add_species()].
#' @template dbh_unit
#'
#' @family functions to manipulate equations
#'
#' @return A nested dataframe with each row containing the data of an equation
#'   type.
#' @export
#'
#' @examples
#' census <- dplyr::sample_n(fgeo.biomass::scbi_tree1, 30)
#' species <- fgeo.biomass::scbi_species
#' census_species <- add_species(
#'   census, species,
#'   site = "scbi"
#' )
#'
#' add_equations(census_species, dbh_unit = "mm")
#' @family constructors
add_equations <- function(data, dbh_unit = guess_dbh_unit(data$dbh)) {
  check_crucial_names(data, c("species", "site", "rowid"))
  inform_if_guessed_dbh_unit(dbh_unit)
  add_equations_memoised(data, dbh_unit = dbh_unit)
}

warn_if_species_missmatch <- function(data, eqn) {
  to_match <- data[["species"]]
  available <- unique(
    eqn[eqn$site %in% unique(data$site), , drop = FALSE]$species
  )
  .matching <- to_match %in% available

  if (sum(!.matching) > 0) {
    missmatching <- paste0(sort(unique(to_match[!.matching])), collapse = ", ")
    ui_warn("
      Can't find equations matching these species:
      {missmatching}
    ")
  }

  invisible(data)
}

warn_if_missing_equations <- function(data) {
  all_missing <- tapply(data$eqn_id, data$rowid, function(x) all(is.na(x)))
  if (sum(all_missing) > 0) {
    ui_warn(
      "Can't find equations for {sum(all_missing)} rows (inserting `NA`)."
    )
  }

  invisible(data)
}

prefer_expert_equations <- function(data) {
  check_crucial_names(data, "is_generic")

  data %>%
    group_by(.data$rowid) %>%
    filter(replace_na(prefer_false(.data$is_generic), TRUE)) %>%
    ungroup()
}

replace_site <- function(eqn, from, to) {
  eqn_from_here <- mutate(eqn,
    site = dplyr::case_when(
      tolower(.data$site) == from ~ to,
      TRUE ~ .data$site
    )
  )
}
