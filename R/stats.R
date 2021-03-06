#' Estimator 'SP' for the Expected Running Time (ERT)
#'
#' @param data A dataframe or matrix. Each row stores the runtime sample points from
#' several runs
#' @param max_runtime A Numerical vector. Should have the same size as columns of data
#'
#' @return A list containing ERTs, number of succesfull runs and the succes rate
#' @export
#' @examples
#' SP(dsl[[1]]$RT, max(dsl[[1]]$RT))
SP <- function(data, max_runtime) {
  N <- ncol(data)
  M <- nrow(data)

  succ <- apply(data, 1, function(x) sum(!is.na(x)))
  succ_rate <- succ / N
  idx <- is.na(data)

  for (i in seq(M)) {
    data[i, idx[i, ]] <- max_runtime[idx[i, ]]
  }

  list(ERT = rowSums(data) / succ, runs = succ, succ_rate = succ_rate)
}

#' Bootstrapping for running time samples
#'
#' @param x A numeric vector. A sample of the running time.
#' @param max_eval A numeric vector, containing the maximal running time in
#' each run. It should have the same size as x
#' @param bootstrap.size integer, the size of the bootstrapped sample
#'
#' @return A numeric vector of the bootstrapped running time sample
#' @export
#' @examples
#' ds <- dsl[[1]]
#' x <- get_RT_sample(ds, ftarget = 16, output = 'long')
#' max_eval <- get_maxRT(dsl, output = 'long')
#' bootstrap_RT(x$RT, max_eval$maxRT, bootstrap.size = 30)
bootstrap_RT <- function(x, max_eval, bootstrap.size) {
  x_succ <- x[!is.na(x)]
  x_unsucc <- max_eval[is.na(x)]
  n_succ <- length(x_succ)
  n_unsucc <- length(x_unsucc)

  p <- n_succ / length(x)
  N <- rgeom(bootstrap.size, p)

  if (n_succ == 0){
    return (rep(Inf, bootstrap.size))
  }

  sapply(N,
         function(size) {
           if (size > 0)
             x <- sum(sample(x_unsucc, size, replace = T))
           else
             x <- 0
           x <- x + sample(x_succ, 1, replace = T)
         })
}

# TODO: remove the bootstrapping part as it does not make much sense here...
#' Performs a pairwise Kolmogorov-Smirnov test on the bootstrapped running times
#' among a data set
#'
#' @description This function performs a Kolmogorov-Smirnov test on each pair of
#' algorithms in the input x to determine which algorithm gives a significantly
#' smaller running time. The resulting p-values are arranged in a matrix, where
#' each cell (i, j) contains a p-value from the test with alternative hypothesis:
#' the running time of algorithm i is smaller (thus better) than that of j.
#'
#' @param x either a list that contains running time sample for each algorithm as
#' sub-lists, or a DataSetList object
#' @param bootstrap.size integer, the size of the bootstrapped sample. Set to 0 to disable bootstrapping
#' @param ... all other options
#' @return A matrix containing p-values of the test
#' @export
#' @examples
#' pairwise.test(subset(dsl, funcId == 1), 16)
pairwise.test <- function(x, ...) UseMethod('pairwise.test', x)

#' @param max_eval list that contains the maximal running time for each algorithm
#' as sub-lists
#' @export
#' @rdname pairwise.test
pairwise.test.list <- function(x, max_eval, bootstrap.size = 30, ...) {
  if ("DataSetList" %in% class(x)) {
    class(x) <- rev(class(x))
    pairwise.test.DataSetList(x)
  }

  N <- length(x)
  p.value <- matrix(NA, N, N)

  for (i in seq(1, N - 1)) {
    for (j in seq(i + 1, N)) {
      if (bootstrap.size == 0) {
        x1 <- x[[i]]
        x2 <- x[[j]]
      } else {
        x1 <- bootstrap_RT(x[[i]], max_eval[[i]], bootstrap.size)
        x2 <- bootstrap_RT(x[[j]], max_eval[[j]], bootstrap.size)
      }
      if (all(is.na(x1))) {
        if (all(is.na(x2))) {
          next
        }
        else {
          p.value[i, j] <- 1
          p.value[j, i] <- 0
        }
      }
      else if (all(is.na(x2))) {
        p.value[i, j] <- 0
        p.value[j, i] <- 1
      }
      else {
        options(warn = -1)
        p.value[i, j] <- ks.test(x1, x2, alternative = 'greater', exact = F)$p.value
        p.value[j, i] <- ks.test(x1, x2, alternative = 'less', exact = F)$p.value
        options(warn = 0)
      }
    }
  }

  p.value.adjust <- p.adjust(as.vector(p.value), method = 'holm')
  p.value <- matrix(p.value.adjust, N, N)
  colnames(p.value) <- rownames(p.value) <- names(x)
  p.value
}

#' @param ftarget float, the target value used to determine the running / hitting
#' @param which wheter to do fixed-target ('by_FV') or fixed-budget ('by_RT') comparison
#' time
#' @export
#' @rdname pairwise.test
pairwise.test.DataSetList <- function(x, ftarget, bootstrap.size = 0, which = 'by_FV', ...) {
  if (which == 'by_FV') {
    dt <- get_RT_sample(x, ftarget, output = 'long')
    maxRT <- get_maxRT(x, output = 'long')
    maxRT <- split(maxRT$maxRT, maxRT$algId)
    s <- split(dt$RT, dt$algId)
  }
  else if (which == 'by_RT') {
    dt <- get_FV_sample(x, ftarget, output = 'long')
    maxRT <- NULL
    if (bootstrap.size > 0) warning("Bootstrapping is currently not supported for
                                    fixed-budget statistics.")
    bootstrap.size = 0
    s <- split(dt$`f(x)`, dt$algId)
  }
  else stop("Unsupported argument 'which'. Available options are 'by_FV' and 'by_RT'")
  
  return(pairwise.test.list(s, maxRT, bootstrap.size))
}

# TODO: move those two functions to a separate file
# TODO: review / re-write this function
#' Function for generating sequences of function values
#'
#' @param FV A list of function values
#' @param from Starting function value. Will be replaced by min(FV) if it is NULL or too small
#' @param to Stopping function value. Will be replaced by max(FV) if it is NULL or too large
#' @param by Stepsize of the sequence. Will be replaced if it is too small
#' @param length.out Number of values in the sequence.
#'   'by' takes preference if both it and length.out are provided.
#' @param scale Scaling of the sequence. Can be either 'linear' or 'log', indicating a
#'   linear or log-linear spacing respectively. If NULL, the scale will be predicted
#'   based on FV
#'
#' @return A sequence of function values
#' @export
#' @examples
#' FVall <- get_runtimes(dsl)
#' seq_FV(FVall, 10, 16, 1, scale='linear')
seq_FV <- function(FV, from = NULL, to = NULL, by = NULL, length.out = NULL, scale = NULL) {
  from <- max(from, min(FV))
  to <- min(to, max(FV))

  rev_trans <- function(x) x

  # Auto detect scaling
  # TODO: Improve this detection (based on FV?). Currently very arbitrary
  if (is.null(scale)) {
    if (to < 0 || from < 0)
      scale <- 'linear'
    else if (abs(log10(mean(FV)) - log10(median(FV))) > 1)
      scale <- 'log'
    else
      scale <- 'linear'
  }

  if (scale == 'log') {
    trans <- log10
    rev_trans <- function(x) 10 ^ x
    # TODO: Better way to deal with negative values
    #       set lowest possible target globally instead of arbitrary 1e-12
    from <- max(1e-12, from)
    to <- max(1e-12 ,to)
    from <- trans(from)
    to <- trans(to)
  }

  #Avoid generating too many samples
  if (!is.null(by)) {
    nr_samples_generated <- (to - from) / by
    if (nr_samples_generated > getOption("IOHanalyzer.max_samples", default = 100)) {
      by <- NULL
      if (is.null(length.out))
        length.out <- getOption("IOHanalyzer.max_samples", default = 100)
    }
  }

  if (is.null(by) || by > to - from) {
    if (is.null(length.out)) {
      length.out <- 10
      args <- list(from = from, to = to, by = (to - from) / (length.out - 1))
    } else
      args <- list(from = from, to = to, length.out = length.out)
  } else
    args <- list(from = from, to = to, by = by)

  # tryCatch({
  do.call(seq, args) %>%
    c(from, ., to) %>%    # always include the starting / ending value
    unique %>%
    rev_trans
  # }, error = function(e) {
  # c()
  # })
}

# TODO: review / re-write this function
#' Function for generating sequences of runtime values
#'
#' @param RT A list of runtime values
#' @param from Starting runtime value. Will be replaced by min(RT) if it is NULL or too small
#' @param to Stopping runtime value. Will be replaced by max(RT) if it is NULL or too large
#' @param by Stepsize of the sequence. Will be replaced if it is too small
#' @param length.out Number of values in the sequence.
#'   'by' takes preference if both it and length.out are provided.
#' @param scale Scaling of the sequence. Can be either 'linear' or 'log', indicating a
#'   linear or log-linear spacing respectively.
#'
#' @return A sequence of runtime values
#' @export
#' @examples
#' RTall <- get_runtimes(dsl)
#' seq_RT(RTall, 0, 500, length.out=10, scale='log')
seq_RT <- function(RT, from = NULL, to = NULL, by = NULL, length.out = NULL,
                   scale = 'linear') {
  rev_trans <- function(x) x

  # Do this first to avoid the log-values being overwritten.
  from <- max(from, min(RT))
  to <- min(to, max(RT))

  if (scale == 'log') {
    RT <- log10(RT)
    rev_trans <- function(x) 10 ^ x
    if (!is.null(from))
      from <- log10(from)
    if (!is.null(to))
      to <- log10(to)
    if (!is.null(by))
      by <- log10(by)
  }

  #Avoid generating too many samples
  if (!is.null(by)) {
    nr_samples_generated <- (to - from) / by
    if (nr_samples_generated > getOption("IOHanalyzer.max_samples", default = 100)) {
      by <- NULL
      if (is.null(length.out))
        length.out <- getOption("IOHanalyzer.max_samples", default = 100)
    }
  }

  # Also reset by if it is too large
  if (is.null(by) || by > to - from) {
    if (is.null(length.out)) {
      length.out <- 10
      args <- list(from = from, to = to, by = (to - from) / (length.out - 1))
    } else
      args <- list(from = from, to = to, length.out = length.out)
  } else
    args <- list(from = from, to = to, by = by)

  do.call(seq, args) %>%
    c(from, ., to) %>%    # always include the starting / ending value
    unique %>%
    rev_trans %>%
    round
}

# TODO: implement the empirical p.m.f. for runtime
EPMF <- function() {

}

#' Empirical Cumulative Dsitribution Function of Runtime of a single data set
#'
#' @param ds A DataSet or DataSetList object.
#' @param ftarget A Numerical vector. Function values at which runtime values are consumed
#' @param ... Arguments passed to other methods
#'
#' @return a object of type 'ECDF'
#' @export
#' @examples
#' ECDF(dsl,c(12,14))
#' ECDF(dsl[[1]],c(12,14))
ECDF <- function(ds, ftarget, ...) UseMethod("ECDF", ds)

# TODO: also implement the ecdf functions for function values and parameters
#' @rdname ECDF
#' @export
ECDF.DataSet <- function(ds, ftarget, ...) {
  runtime <- get_RT_sample(ds, ftarget, output = 'long')$RT
  runtime <- runtime[!is.na(runtime)]
  if (length(runtime) == 0)
    fun <- ecdf(Inf)
  else
    fun <- ecdf(runtime)

  class(fun)[1] <- 'ECDF'
  attr(fun, 'min') <- min(runtime)
  attr(fun, 'samples') <- length(runtime)
  attr(fun, 'max') <- max(runtime)  # the sample can be retrieved by knots(fun)
  fun
}

# TODO: review / re-write this function
#' @rdname ECDF
#' @export
ECDF.DataSetList <- function(ds, ftarget, ...) {
  if (length(ds) == 0) return(NULL)

  dims <- unique(get_dim(ds))
  funcs <- unique(get_funcId(ds))

  if (is.data.table(ftarget)) {
    runtime <- sapply(seq(nrow(ftarget)), function(i) {
      if (length(dims) > 1 && length(funcs) > 1) {
        names_temp <- ftarget[i][[1]] %>%
          strsplit(., ';')
        FuncId <- names_temp[[1]][[1]]
        Dim <- names_temp[[1]][[2]]
      }
      else if (length(dims) > 1) {
        FuncId <- funcs[[1]]
        Dim <- ftarget[i][[1]]
      }
      else if (length(funcs) > 1) {
        FuncId <- ftarget[i][[1]]
        Dim <- dims[[1]]
      }
      data <- subset(ds, funcId == FuncId, DIM == Dim)
      if (length(data) == 0) return(NA)
      temp_targets <- ftarget[i] %>%
        unlist %>%
        as.numeric
      names(temp_targets) <- NULL
      res <- get_RT_sample(data, temp_targets[2:11], output = 'long')$RT
      res[is.na(res)] <- Inf
      res
    }) %>%
      unlist
  } else if (is.list(ftarget)) {
    runtime <- sapply(seq_along(ftarget), function(i) {
      if(length(dims) > 1 && length(funcs) >1){
        names_temp <- names(ftarget[i])[[1]] %>%
          strsplit(., ';')
        FuncId <- names_temp[[1]][[1]]
        Dim <- names_temp[[1]][[2]]
      }
      else if(length(dims) > 1){
        FuncId <- funcs[[1]]
        Dim <- names(ftarget[i])[[1]]
      }
      else if(length(funcs) > 1){
        FuncId <- names(ftarget[i])[[1]]
        Dim <- dims[[1]]
      } else {
        FuncId <- funcs[[1]]
        Dim <- dims[[1]]
      }
      data <- subset(ds, funcId == FuncId, DIM == Dim)
      if (length(data) == 0) return(NA)
      res <- get_RT_sample(data, ftarget[[i]], output = 'long')$RT
      res[is.na(res)] <- Inf
      res
    }) %>%
      unlist
  } else {
    runtime <- get_RT_sample(ds, ftarget, output = 'long')$RT
    runtime[is.na(runtime)] <- Inf
  }


  if (length(runtime) == 0) return(NULL)

  fun <- ecdf(runtime)
  class(fun)[1] <- 'ECDF'
  attr(fun, 'min') <- min(runtime)
  attr(fun, 'max') <- max(runtime)  # the sample can be retrieved by knots(fun)
  fun
}

#' Area Under Curve (Empirical Cumulative Dsitribution Function)
#'
#' @param fun A ECDF object.
#' @param from double. Starting point of the area on x-axis
#' @param to   double. Ending point of the area on x-axis
#'
#' @return a object of type 'ECDF'
#' @export
#' @examples
#' ecdf <- ECDF(dsl,c(12,14))
#' AUC(ecdf, 0, 100)
AUC <- function(fun, from = NULL, to = NULL) UseMethod('AUC', fun)

#' @rdname AUC
#' @export
AUC.ECDF <- function(fun, from = NULL, to = NULL) {
  if (is.null(from))
    from <- attr(fun, 'min')
  if (is.null(to))
    to <- attr(fun, 'max')

  if (is.null(fun))
    0
  else
    integrate(fun, lower = from, upper = to, subdivisions = 1e3L)$value / (to - from)
}

#' Generate datatables of runtime or function value targets for a DataSetList
#'
#' Only one target is generated per (function, dimension)-pair, as opposed to the
#' function `get_default_ECDF_targets`, which generates multiple targets.
#'
#' @param dsList A DataSetList
#' @param which Whether to generate fixed-target ('by_FV') or fixed-budget ('by_RT') targets
#'
#' @return a data.table of targets
#' @export
#' @examples
#' get_target_dt(dsl)
get_target_dt <- function(dsList, which = 'by_RT') {
  vals <- c()
  funcs <- get_funcId(dsList)
  dims <- get_dim(dsList)
  dt <- as.data.table(expand.grid(funcs, dims))
  colnames(dt) <- c("funcId", "DIM")
  if (which == 'by_RT') {
    target_func <- get_target_FV
  }
  else if (which == 'by_FV') {
    target_func <- get_target_RT
  }
  else stop("Invalid argument for `which`; can only be `by_FV` or `by_RT`.")
  targets <- apply(dt, 1,
                   function(x) {target_func(subset(dsList, funcId == x[[1]], DIM == x[[2]]))})
  dt[, target := targets]

  return(dt)
}

#' Helper function for `get_target_dt`
#' @noRd
get_target_FV <- function(dsList){
  vals <- get_FV_summary(dsList, Inf)[[paste0(100*getOption("IOHanalyzer.quantiles", 0.02)[[1]], '%')]]
  if (is.null(attr(dsList, 'maximization')) || attr(dsList, 'maximization')) {
    return(max(vals))
  }
  else {
    return(min(vals))
  }
}

#' Helper function for `get_target_dt`
#' @noRd
get_target_RT <- function(dsList){
  return(max(get_runtimes(dsList)))
}

#' Glicko2 raning of algorithms
#'
#' This procedure ranks algorithms based on a glicko2-procedure.
#' Every round (total nr_rounds), for every function and dimension of the datasetlist,
#' each pair of algorithms competes. This competition samples a random runtime for the
#' provided target (defaults to best achieved target). Whichever algorithm has the lower
#' runtime wins the game. Then, from these games, the glicko2-rating is determined.
#'
#' @param dsl The DataSetList, can contain multiple functions and dimensions, but should have the
#' same algorithms for all of them
#' @param nr_rounds The number of rounds to run. More rounds leads to a more accurate ranking.
#' @param which Whether to use fixed-target ('by_FV') or fixed-budget ('by_RT') perspective
#' @param target_dt Custom data.table target value to use. When NULL, this is selected automatically.
#' @return A dataframe containing the glicko2-ratings and some additional info
#'
#' @export
#' @examples
#' glicko2_ranking(dsl, nr_round = 25)
#' glicko2_ranking(dsl, nr_round = 25, which = 'by_RT')
glicko2_ranking <- function(dsl, nr_rounds = 100, which = 'by_FV', target_dt = NULL){
  req(length(get_algId(dsl)) > 1)

  if (!is.null(target_dt) && !('data.table' %in% class(target_dt))) {
    warning("Provided `target_dt` argument is not a data.table")
    target_dt <- NULL
  }

  if (is.null(target_dt))
    target_dt <- get_target_dt(dsl, which)

  if (!(which %in% c('by_FV', 'by_RT')))
    stop("Invalid argument: 'which' can only be 'by_FV' or 'by_RT'")
  p1 <- NULL
  p2 <- NULL
  scores <- NULL
  weeks <- NULL
  get_dims <- function(){
    dims <- get_dim(dsl)
    if (length(dims) > 1) {
      dims <- sample(dims)
    }
    dims
  }
  get_funcs <- function(){
    funcs <- get_funcId(dsl)
    if (length(funcs) > 1) {
      funcs <- sample(funcs)
    }
    funcs
  }
  n_algs = length(get_algId(dsl))
  alg_names <- NULL
  for (k in seq(1,nr_rounds)) {
    for (dim in get_dims()) {
      targets_temp <- target_dt[target_dt$DIM == dim]
      for (fid in get_funcs()) {
        dsl_s <- subset(dsl, funcId == fid && DIM == dim)
        if (which == 'by_FV') {
          target <- targets_temp[targets_temp$funcId == fid]$target
          x_arr <- get_RT_sample(dsl_s, target)
          win_operator <- `<`
        }
        else {
          target <- targets_temp[targets_temp$funcId == fid]$target
          x_arr <- get_FV_sample(dsl_s, target)
          win_operator <- ifelse(attr(dsl, 'maximization'), `>`, `<`)
        }
        vals = array(dim = c(n_algs,ncol(x_arr) - 4))
        for (i in seq(1,n_algs)) {
          z <- x_arr[i]
          y <- as.numeric(z[,5:ncol(x_arr)])
          vals[i,] = y
        }
        if (is.null(alg_names)) alg_names <- x_arr[,3]

        for (i in seq(1,n_algs)) {
          for (j in seq(i,n_algs)) {
            if (i == j) next
            weeks <- c(weeks, k)
            s1 <- sample(vals[i,], 1)
            s2 <- sample(vals[j,], 1)
            if (is.na(s1)) {
              if (is.na(s2)) {
                won <- 0.5
              }
              else{
                won <- 0
              }
            }
            else{
              if (is.na(s2)) {
                won <- 1
              }
              else if (s1 == s2) {
                won <- 0.5 #Tie
              }
              else {
                won <- win_operator(s1, s2)
              }
            }
            p1 <- c(p1, i)
            p2 <- c(p2, j)
            scores <- c(scores, won)

          }
        }
      }
    }
  }
  # weeks <- seq(1,1,length.out = length(p1))
  games <- data.frame(Weeks = weeks, Player1 = p1, Player2 = p2, Scores = as.numeric(scores))
  lout <- glicko2(games, init =  c(1500,350,0.06))
  lout$ratings$Player <- alg_names[lout$ratings$Player]
  lout
}
