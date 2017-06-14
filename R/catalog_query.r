# ===============================================================================
#
# PROGRAMMERS:
#
# jean-romain.roussel.1@ulaval.ca  -  https://github.com/Jean-Romain/lidR
#
# COPYRIGHT:
#
# Copyright 2016 Jean-Romain Roussel
#
# This file is part of lidR R package.
#
# lidR is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# ===============================================================================


#' Extract LiDAR data based on a set of coordinates
#'
#' When the user has a set of (x, y) coordinates corresponding to a region of interest (ROI),
#' a ground inventory for example, they can automatically extract the lidar data associated
#' with the ROIs from a \link[lidR:catalog]{Catalog}. The algorithm will do this even for ROIs
#' falling on the edges of one or more tiles.\cr
#' It works only for tiles that are arranged in gridlines.
#'
#' @aliases catalog_queries
#' @param obj A Catalog object

#' @param x vector. A set of x coordinates corresponding to the center of the ROI
#' @param y vector. A set of y coordinates corresponding to the center of the ROI
#' @param r numeric or vector. A radius or a set of radii of the ROI. If only
#' r is provided (r2 = NULL) it will extract data falling onto a disc.
#' @param r2 numeric or vector. A radius or a set of radii of plots. If r2
#' is provided, the selection turns into a rectangular ROI. If r = r2 it is a square.
#' @param roinames vector. A set of ROI names (the ID of the plots, for example)
#' @param filter character. Streaming filter while reading the files (see \link{readLAS}).
#' @param ... internal use only.
#' @return A list of LAS objects
#' @seealso
#' \link[lidR:readLAS]{readLAS}
#' \link[lidR:catalog]{Catalog}
#' \link[lidR:catalog_queries]{catalog_queries}
#' @export catalog_queries
#' @examples
#' \dontrun{
#' # Global option to display a progressbar
#' lidr_option(progress = TRUE)
#'
#' # Build a Catalog
#' catalog = catalog("<Path to a folder containing a set of .las or .laz files>")
#'
#' # Get coordinates from an external file
#' X = runif(30, 690000, 800000)
#' Y = runif(30, 5010000, 5020000)
#' R = 25
#'
#' # Return a List of 30 circular LAS objects of 25 m radius
#' catalog %>% catalog_queries(X, Y, R)
#'
#' # Return a List of 30 square LAS objects of 50x50 m
#' catalog %>% catalog_queries(X, Y, R, R)
#' }
catalog_queries = function(obj, x, y, r, r2 = NULL, roinames = NULL, filter = "", ...)
{
  . <- tiles <- NULL

  objtxt = lazyeval::expr_text(obj)
  xtxt   = lazyeval::expr_text(x)
  ytxt   = lazyeval::expr_text(y)
  rtxt   = lazyeval::expr_text(r)

  if (!is(obj, "Catalog"))
    stop(paste0(objtxt, " is not a Catalog."), call. = FALSE)

  if (length(x) != length(y))
    stop(paste0(xtxt, " is not same length as ", ytxt), call. = FALSE)

  if (length(r) > 1 & (length(x) != length(r)))
    stop(paste0(xtxt, " is not same length as ", rtxt), call. = FALSE)

  param = lazyeval::dots_capture(...)

  nplot = length(x)
  shape = if (is.null(r2)) 0 else 1

  if (is.null(roinames)) roinames = paste0("ROI", 1:nplot)

  verbose("Indexing files...")

  # Make an index of the file in which are each query
  lasindex = obj %>% catalog_index(x, y, r, r2, roinames)

  # Remove potential unproper queries (out of existing files)
  keep = lasindex[, length(tiles[[1]]) > 0, by = roinames]$V1
  lasindex = lasindex[keep]
  roinames = roinames[keep]

  # Transform as list
  lasindex = apply(lasindex, 1, as.list)

  # Recompute the number of queries
  nplot = length(lasindex)

  verbose("Extracting data...")

  # Internal use only to force to disable the progressbar against what is in the options
  if (LIDROPTIONS("progress") & is.null(param$disable_bar))
    p = utils::txtProgressBar(max = nplot, style = 3)
  else
    p = NULL

  # Internal use only to force one core computation against what is requested in the options
  if (nplot <= 2 | !is.null(param$no_multicore))
    mc.cores = 1
  else
    mc.cores = CATALOGOPTIONS("multicore")

  if (mc.cores == 1)
    output = lapply(lasindex, .getQuery, shape, filter, p)
  else
  {
    cl = parallel::makeCluster(mc.cores, outfile = "")
    parallel::clusterExport(cl, varlist = c(utils::lsf.str(envir = globalenv()), ls(envir = environment())), envir = environment())
    output = parallel::parLapply(cl, lasindex, .getQuery, shape, filter)
    parallel::stopCluster(cl)
  }

  output = unlist(output)
  output = output[match(roinames, names(output))]  # set back to the original order

  return(output)
}

.getQuery = function(query, shape, filter, p = NULL, ...)
{
  x <- y <- r <- r2 <- NULL

  if (shape == 0)
    clip_filter = query %$% paste("-inside_circle", x, y, r)
  else
    clip_filter = query %$% paste("-inside", x - r, y - r2, x + r, y + r2)

  filter = paste(filter, clip_filter)

  lidardata = list(readLAS(query$tiles, all = TRUE, filter = filter))
  names(lidardata) = query$roinames

  if (!is.null(p))
  {
    i = utils::getTxtProgressBar(p) + 1
    utils::setTxtProgressBar(p, i)
  }
  else
    cat(sprintf("%s ", query$roinames))

  return(lidardata)
}

