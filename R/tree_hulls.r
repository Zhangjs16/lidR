# ===============================================================================
#
# PROGRAMMERS:
#
# jean-romain.roussel.1@ulaval.ca  -  https://github.com/Jean-Romain/lidR
#
# COPYRIGHT:
#
# Copyright 2016-2018 Jean-Romain Roussel
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


#' Compute the hull of each tree.
#'
#' Compute the hull of each segmented tree. The hull can be convex, concave or a bounding box (see
#' details and references).
#'
#' The concave hull method under the hood is described in Park & Oh (2012). The function relies on
#' the \link[concaveman:concaveman]{concaveman} function which itself is a wrapper around
#' \href{https://github.com/mapbox/concaveman}{Vladimir Agafonking's implementation}.
#'
#' @template param-las
#' @param type character. Hull type. Can be 'convex', 'concave' or 'bbox'.
#' @param concavity numeric. If \code{type = "concave"}, a relative measure of concavity. 1 results
#' in a relatively detailed shape, Infinity results in a convex hull.
#' @param length_threshold numeric. If \code{type = "concave"}, when a segment length is below this
#' threshold, no further detail is added. Higher values result in simpler shapes.
#' @param attribute character. The attribute where the ID of each tree is stored. In lidR, the default is
#' "treeID".
#'
#' @return A \code{SpatialPolygonsDataFrame}. If a tree has less than 4 points it is not considered.
#'
#' @template LAScatalog
#' @template section-supported-option-tree_detection
#'
#' @export
#'
#' @references Park, J. S., & Oh, S. J. (2012). A new concave hull algorithm and concaveness measure
#' for n-dimensional datasets. Journal of Information science and engineering, 28(3), 587-600.
#'
#' @examples
#' LASfile <- system.file("extdata", "MixedConifer.laz", package="lidR")
#' las = readLAS(LASfile, select = "xyz0", filter = "-drop_z_below 0")
#'
#' # Note: the trees are already segmented in this file and the IDs
#' # are stored in extrabytes 0.
#'
#' convex_hulls = tree_hulls(las)
#' sp::plot(convex_hulls)
#'
#' bbox_hulls = tree_hulls(las, "bbox")
#' sp::plot(bbox_hulls)
#'
#' \dontrun{
#' concave_hulls = tree_hulls(las, "concave")
#' sp::plot(concave_hulls)
#' }
tree_hulls = function(las, type = c("convex", "concave", "bbox"), concavity = 3, length_threshold = 0, attribute = "treeID")
{
  UseMethod("tree_hulls", las)
}

#' @export
tree_hulls.LAS = function(las, type = c("convex", "concave", "bbox"), concavity = 3, length_threshold = 0, attribute = "treeID")
{
  stopifnotlas(las)
  type <- match.arg(type)
  assert_is_a_number(concavity)
  assert_all_are_non_negative(concavity)
  assert_is_a_number(length_threshold)
  assert_all_are_non_negative(length_threshold)
  assert_is_a_string(attribute)

  X <- Y <- tree <- NULL

  if (type == "convex")
    dt <- las@data[, stdtreehullconvex(X,Y, .GRP), by = attribute]
  else if (type == "concave")
  {
    if (!requireNamespace("concaveman", quietly = TRUE))
      stop("'concaveman' package is needed for this function to work.")

    dt <- las@data[, stdtreehullconcave(X,Y, .GRP, concavity, length_threshold), by = attribute]
  }
  else
    dt <- las@data[, stdtreehullbbox(X,Y, .GRP), by = attribute]

  data.table::setnames(dt, names(dt), c("tree", "poly"))
  dt <- dt[!is.na(tree)]

  spoly <- sp::SpatialPolygons(dt$poly)

  for (i in 1:length(spoly)) spoly@polygons[[i]]@ID <- as.character(i)

  data <- data.frame(dt[, 1])
  names(data) <- attribute
  spdf <- sp::SpatialPolygonsDataFrame(spoly, data)
  sp::proj4string(spdf) <- las@proj4string

  return(spdf)
}

#' @export
tree_hulls.LAScluster = function(las, type = c("convex", "concave", "bbox"), concavity = 3, length_threshold = 0, attribute = "treeID")
{
  x = readLAS(las)
  if (is.empty(x)) return(NULL)
  metrics = tree_hulls(x, type, concavity, length_threshold, attribute)
  bbox = raster::extent(las)
  metrics = raster::crop(metrics, bbox)
  return(metrics)
}

#' @export
tree_hulls.LAScatalog = function(las, type = c("convex", "concave", "bbox"), concavity = 3, length_threshold = 0, attribute = "treeID")
{
  options <- list(need_buffer = TRUE, drop_null = TRUE, need_output_file = FALSE)
  output  <- catalog_apply(las, tree_hulls, type = type, concavity = concavity, length_threshold = length_threshold, attribute = attribute, .options = options)

  if (opt_output_files(las) == "")
  {
    output <- do.call(rbind, output)
    output@proj4string = las@proj4string
  }
  else
  {
    output <- unlist(output)
  }

  return(output)
}

stdtreehullconvex = function(x,y, grp)
{
  if (length(x) < 4)
    return(NULL)

  i = grDevices::chull(x,y)
  i = c(i, i[1])
  P = cbind(x[i], y[i])
  poly = sp::Polygon(P)
  poly = sp::Polygons(list(poly), ID = grp)

  list(poly = list(poly))
}

stdtreehullconcave = function(x,y, grp, concavity, length_threshold)
{
  if (length(x) < 4)
    return(NULL)

  P = concaveman::concaveman(cbind(x,y), concavity, length_threshold)
  poly = sp::Polygon(P)
  poly = sp::Polygons(list(poly), ID = grp)

  list(poly = list(poly))
}

stdtreehullbbox = function(x,y, grp)
{
  if (length(x) < 4)
    return(NULL)

  xmin = min(x)
  ymin = min(y)
  xmax = max(x)
  ymax = max(y)

  x = c(xmin, xmax, xmax, xmin, xmin)
  y = c(ymin, ymin, ymax, ymax, ymin)
  P = cbind(x, y)
  poly = sp::Polygon(P)
  poly = sp::Polygons(list(poly), ID = grp)

  list(poly = list(poly))
}

