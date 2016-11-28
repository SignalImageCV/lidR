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



#' Apply a function to a set of tiles using several cores.
#'
#' The function has different behaviours on MS Windows and Unix platform, read carfully
#' the doc, sections "Detail", "Unix" and "Windows". This function provide an immediatly usable
#' parallel computing tool but users confortable with multi-core process are better
#' to use there own code to have a more flexible tools.
#'
#' When users have a set of LAS data organized in several tiles it can apply a user function to each tile.
#' Examples section describes the procedure to apply to each file beginning with data loading (see example).
#' The function automatically detect you operating system and apply the best parallelisation method for your system.
#' Unix mechanism is more powerfull. However it is not compatible with Windows (see sections Unix and Windows).
#' The Windows mechanism is more complex to use.\cr\cr
#' WARNING: there is no buffer mechanism to protect the process again edge artifacs. See section "Edge artifacts".
#'
#' @section Unix:
#'
#' In Unix platform (GNU/Linux and Mac), the parallelization rely on fork-exec technique
#' (see \link[parallel:mclapply]{mclapply}). It means, among others, that each child process
#' has an acces to the parent process' memory. For example you can call functions from .GlobalEnv
#' or any orther environnement. If a code written for Unix is ran on Windows it will works
#' but with only one core like a normal loop. If Unix users want to share their code
#' to Windows users they are better to force the function to use clustering method.
#'
#' @section Windows:
#'
#' In Windows platform (MS Windows), the parallelization rely on cluster
#' (see \link[parallel:parLapplyLB]{parLapplyLB}). It works both for Unix and Windows
#' but it is much more memory intensive and very not userfriendly as the user must
#' export himself all the object he needs. Indeed cluster technique implies, among others,
#' that each child process cannot acces to the parent process memory.
#' If you want to make the process on 1 core only, the function use the \code{unix}
#' mode which works like a regular loop (non parallel computing).
#'
#' @section Egde artifacts:
#'
#' It is very important to take precautions to avoid "edge artifacts" when processing LiDAR tiles.
#' If the points from neighboring tiles are not included during certain process it might involve edge artifacts
#' at the edges of the tiles. For exemple, empty or incomplete pixels in a rasterization process. The lidR package
#' does not provide internal tools to deal with buffer as it is design for experimental purposes not to output professional
#' products. The users could, for example, filter the invalid/corrupted data at the edge of the tiles from the output.
#'
#' @aliases process_parallel
#' @param x  A Catalog object
#' @param func A function which has one parameter: the name of a .las or .laz file (see example)
#' @param platform charater. Can be "windows" or "unix". Default is autodetect. See sections "Details", "Unix" and  "Windows".
#' @param mc.cores integer. Number of cores used. Default is the number of cores you have on your computer.
#' @param combine character. The function used to merge the outputs of the \code{func} function.
#' @param varlist charaters vector. For windows mode, character vector of names of objects to export.
#' @examples
#' \dontrun{
#' # Visit http://jean-romain.github.io/lidR/catalog.html for more examples
#' # about this function
#'
#' # 1. build a project
#' project = Catalog("folder")
#' plot(project)
#'
#' # 2. load the shapefile you need to filter your points (if needed).
#' lake = rgdal::readOGR("folder", "shapefile")
#'
#' # 3 build the function which analyses a tile (a file).
#' # This function input is only the path of a .las file
#' # see the following template
#'
#' analyse_tile = function(LASFile)
#' {
#'   # Load the data
#'   lidar = readLAS(LASFile)
#'
#'   # Associate geographic data with lidar points (if needed)
#'   lidar %<>% classify_from_shapefile(lake, field="inlake")
#'
#'   # filter lake
#'   lidar %<>% lasfilter(lake == FALSE)
#'   # compute all metrics
#'   metrics = grid_metrics(lidar, 20, myMetrics(X,Y,Z,Intensity,ScanAngle,pulseID))
#'
#'   return(metrics)
#' }

#' #### UNIX #####
#' # This code works only on Unix platforms because it rely on shared memory
#' # between all the process. See below for a Windows compatible code.
#'
#' # 4. Process the project. By default it detects how many cores you have. But you can add
#' # an optional parameter mc.core = 3.
#' output = project %>% process_parallel(analyse_tile)
#'
#' #### WINDOWS #####
#' # This code works both on Unix and Windows platforms. But it is more memory intensive
#' # and more complex (here the exemple is simple enought so it does not change a lot of things)
#'
#' # 4. Process the project. By default it detects how many cores you have. But you can add
#' # an optional parameter mc.core = 3.
#' export = c("readLAS", "classify_from_shapefile", "grid_metrics",
#'            "myMetrics", "lake", "lasfilter", "%<>%")
#' output = project %>% process_parallel(analyse_tile, varlist = export, platform = "windows")
#' }
#' @seealso
#' \link[lidR:Catalog-class]{catalog}
#' \link[parallel:mclapply]{mclapply}
#' \link[parallel:parLapplyLB]{parLapplyLB}
#' \link[lidR:classify_from_shapefile]{classify_from_shapefile}
#' \link[lidR:grid_metrics]{grid_metrics}
#' @export process_parallel
#' @importFrom parallel mclapply detectCores
setGeneric("process_parallel", function(x, func, platform=.Platform$OS.type, mc.cores = parallel::detectCores(), combine = "rbind", varlist = ""){standardGeneric("process_parallel")})

#' @rdname process_parallel
setMethod("process_parallel", "Catalog",
	function(x, func, platform=.Platform$OS.type, mc.cores = parallel::detectCores(), combine = "rbind", varlist = "")
	{
	    cat("Begin parallel processing... \n")

      ti = Sys.time()

      files = x@headers$filename

      if(platform == "unix" | mc.cores == 1)
      {
        cat("Platform mode: unix (fork-exec)\n")
        cat("Num. of cores:", mc.cores, "\n\n")
        out = parallel::mclapply(files, func, mc.preschedule = FALSE, mc.cores = mc.cores)
      }
      else
      {
        cat("Platform mode: windows (cluster)\n")
        cat("Num. of cores:", mc.cores, "\n\n")
        cl <- parallel::makeCluster(getOption("cl.cores", mc.cores))
        parallel::clusterExport(cl, varlist, envir = environment())
        out = parallel::parLapplyLB(cl, files, func)
        parallel::stopCluster(cl)
      }

      out = do.call(combine, out)

      gc()

      tf = Sys.time()
      cat("Process done in", round(difftime(tf, ti, units="min"), 1), "min\n\n")

      return(out)
	}
)