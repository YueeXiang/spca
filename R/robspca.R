#' @title Robust Sparse Principal Component Analysis (robspca).
#
#' @description Implementation of robust SPCA useing variable projection as an optimization strategy.
#
#' @details
#' Sparse principal component analysis computes a is a modern variant of PCA for high-dimensional data analysis.
#' SPCA provides aims to find a parsimonious model to describe the data and to overcome some of the shortcomings of PCA.
#' Specfically, SPCA attempts to find sparse weight vectors, i.e., a weight vector with only a few `active' (nonzero) values.
#' This improves the interpretability, because the principal components are formed as a linear combination of
#' only a few of the original variables. This approach avoids also overfitting in a high-dimensional data setting where the
#' number of variables \eqn{p} is greater than the number of observations \eqn{n}, i.e., \eqn{p > n}.
#'
#' The parsimonious model is obtained by introducing prior information such as sparsity promoting regularizers. More concreatly,
#' given an \eqn{(m,n)} matrix \eqn{X} input matrix, robust SPCA attemps seperate the input matrix into a low-rank component and
#' a sparse component. The following objective function is minimized:
#'
#' \deqn{ f(A,B) = \tfrac{1}{2}\fnorm{X - X B A^\top - S}}^2 + \psi(B) + \gamma |S|_1 }
#'
#' where \eqn{B} is the sparse weight (loadings) matrix and \eqn{A} is an orthonormal matrix.
#' \eqn{\psi} denotes a sparsity inducing regularizer such as the LASSO (l1 norm) or the elastic net
#' (a combination of the l1 and l2 norm). \eqn{S} captures grossly corrupted outliers in the data.
#'
#' The principal components \eqn{Z} are then formed as
#'
#' \deqn{ Z = X B }{Z = X %*% B}.
#'
#' The data can be approximately rotated back as
#'
#' \deqn{ \tilde{X} = Z A^\top }{Xtilde = Z %*% t(A)}.
#'
#' The print and summary method can be used to present the results in a nice format.
#'
#'
#'
#' @param X       array_like; \cr
#'                a real \eqn{(n, p)} input matrix (or data frame) to be decomposed.
#'
#' @param k       integer; \cr
#'                specifies the target rank, i.e., number of components to be computed. \eqn{k} should satisfy \eqn{k << min(n,p)}.
#'
#' @param alpha   float; \cr
#'                Sparsity controlling parameter. Higher values lead to sparser components..
#'
#' @param beta    float; \cr
#'                Amount of ridge shrinkage to apply in order to improve conditionin.
#'
#' @param gamma   float; \cr
#'                Sparsity controlling parameter for the error matrix S.
#'                Smaller values lead to a larger amount of noise removeal.
#'
#' @param center  bool; \cr
#'                logical value which indicates whether the variables should be
#'                shifted to be zero centered (\eqn{TRUE} by default).
#'
#' @param scale   bool; \cr
#'                logical value which indicates whether the variables should
#'                be scaled to have unit variance (\eqn{FALSE} by default).
#'
#' @param max_iter integer;
#'                 Maximum number of iterations to perform before exiting.
#'
#' @param tol float;
#'            Stopping tolerance for reconstruction error.
#'
#' @param verbose bool;
#'                If \eqn{TRUE}, display progress.
#'
#'
#'
#'@return \code{spca} returns a list containing the following three components:
#'\item{loadings}{  array_like; \cr
#'           sparse loadings (weight) vector;  \eqn{(p, k)} dimensional array.
#'}
#'
#'\item{transform}{  array_like; \cr
#'           the approximated inverse transform; \eqn{(p, k)} dimensional array.
#'}
#'
#'\item{scores}{  array_like; \cr
#'           the principal component scores; \eqn{(n, k)} dimensional array.
#'}
#'
#'\item{sparse}{  array_like; \cr
#'           sparse matrix capturing outliers in the data; \eqn{(n, p)} dimensional array.
#'}
#'
#'\item{eigenvalues}{  array_like; \cr
#'          the approximated eigenvalues; \eqn{(k)} dimensional array.
#'}
#'
#'\item{center, scale}{  array_like; \cr
#'                     the centering and scaling used.
#'}
#'
#'
#' @author N. Benjamin Erichson, Peng Zheng, and Sasha Aravkin
#'
#' @seealso \code{\link{print.robspca}}, \code{\link{summary.robspca}},
#'  \code{\link{rspca}}, \code{\link{spca}}
#'
#' @examples


#' @export
robspca <- function(X, k=NULL, alpha=1e-4, beta=1e-4, gamma=100, center=TRUE, scale=FALSE, max_iter=1000, tol=1e-5, verbose=TRUE) UseMethod("robspca")

#' @export
robspca.default <- function(X, k=NULL, alpha=1e-4, beta=1e-4, gamma=100, center=TRUE, scale=FALSE, max_iter=1000, tol=1e-5, verbose=TRUE) {

  X <- as.matrix(X)

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Checks
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if (any(is.na(X))) {
    warning("Missing values are omitted: na.omit(X).")
    X <- stats::na.omit(X)
  }

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Init rpca object
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  robspcaObj = list(loadings = NULL,
                 transform = NULL,
                 scores = NULL,
                 eigenvalues = NULL,
                 center = center,
                 scale = scale)

  n <- nrow(X)
  p <- ncol(X)

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Set target rank
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if(is.null(k)) k <- min(n,p)
  if(k > min(n,p)) k <- min(n,p)
  if(k<1) stop("Target rank is not valid!")



  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Center/Scale data
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  if(center == TRUE) {
    robspcaObj$center <- colMeans(X)
    X <- sweep(X, MARGIN = 2, STATS = robspcaObj$center, FUN = "-", check.margin = TRUE)
  } else { robspcaObj$center <- FALSE }

  if(scale == TRUE) {
    robspcaObj$scale <- sqrt(colSums(X**2) / (n-1))
    if(is.complex(robspcaObj$scale)) { robspcaObj$scale[Re(robspcaObj$scale) < 1e-8 ] <- 1+0i
    } else {robspcaObj$scale[robspcaObj$scale < 1e-8] <- 1}
    X <- sweep(X, MARGIN = 2, STATS = robspcaObj$scale, FUN = "/", check.margin = TRUE)
  } else { robspcaObj$scale <- FALSE }


  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Compute SVD for initialization of the Variable Projection Solver
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  svd_init <- svd(X, nu = k, nv = k)

  Dmax <- svd_init$d[1] # l2 norm

  A <- svd_init$v[,1:k]
  B <- svd_init$v[,1:k]

  S = matrix(0, nrow = nrow(X), ncol = ncol(X))

  #--------------------------------------------------------------------
  #   Set Tuning Parameters
  #--------------------------------------------------------------------
  alpha <- alpha *  Dmax**2
  beta <- beta * Dmax**2

  nu <- 1.0 / (Dmax**2 + beta)
  kappa <- nu * alpha

  obj <- c()
  improvement <- Inf

  #--------------------------------------------------------------------
  #   Apply Variable Projection Solver
  #--------------------------------------------------------------------
  noi <- 1
  while (noi <= max_iter && improvement > tol) {

        # Update A:  (X-S)'XB = UDV'
        XS <- X - S
        XB <- X %*% B
        Z <- t(X - S) %*% (X %*% B)
        svd_update <- svd(Z)
        A <- svd_update$u %*% t(svd_update$v)


        # Proximal Gradient Descent to Update B:
        R = XS - XB %*% t(A)
        grad <- t(X) %*% (R %*% A ) - beta * B
        B_temp <- B + nu * grad


        # l1 soft-threshold
        idxH <- which(B_temp > kappa)
        idxL <- which(B_temp <= -kappa)

        B = matrix(0, nrow = nrow(B_temp), ncol = ncol(B_temp))
        B[idxH] <- B_temp[idxH] - kappa
        B[idxL] <- B_temp[idxL] + kappa



      # compute residual
      R <- X - (X %*% B) %*% t(A)

      # l1 soft-threshold
      idxH <- which(R > gamma)
      idxL <- which(R <= -gamma)

      S = matrix(0, nrow = nrow(X), ncol = ncol(X))
      S[idxH] <- R[idxH] - gamma
      S[idxL] <- R[idxL] + gamma


      # compute objective function
      obj <- c(obj, 0.5 * sum(R**2) + alpha * sum(abs(B)) + 0.5 * beta * sum(B**2) +
                 gamma * sum(abs(S)) )

      # Break if obj is not improving anymore
      if(noi > 1){
        improvement <- (obj[noi-1] - obj[noi]) / obj[noi]
      }

      # Trace
      if(verbose > 0 && noi > 1) {
        print(sprintf("Iteration: %4d, Objective: %1.5e, Relative improvement %1.5e", noi, obj[noi], improvement))
      }


      # Next iter
      noi <- noi + 1


  }

  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Update spca object
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  robspcaObj$loadings <- B
  robspcaObj$transform <- A
  robspcaObj$scores <- X %*% B
  robspcaObj$eigenvalues <- svd_update$d / (n - 1)
  robspcaObj$sparse <- S
  robspcaObj$objective <- ob


  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Explained variance and explained variance ratio
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  robspcaObj$sdev <-  sqrt( robspcaObj$eigenvalues )
  robspcaObj$var <- sum( apply( Re(X) , 2, stats::var ) )
  if(is.complex(X)) robspcaObj$var <- Re(robspcaObj$var + sum( apply( Im(X) , 2, stats::var ) ))


  class(robspcaObj) <- "robspca"
  return( robspcaObj )

}


#' @export
print.robspca <- function(x , ...) {
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Print rpca
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  cat("Standard deviations:\n")
  print(round(x$sdev, 3))
  cat("\nEigenvalues:\n")
  print(round(x$eigenvalues, 3))
  cat("\nSparse loadings:\n")
  print(round(x$loadings, 3))
}


#' @export
summary.robspca <- function( object , ... )
{
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # Summary robspca
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  variance = object$sdev**2
  explained_variance_ratio = variance / object$var
  cum_explained_variance_ratio = cumsum( explained_variance_ratio )

  x <- t(data.frame( var = round(variance, 3),
                     sdev = round(object$sdev, 3),
                     prob = round(explained_variance_ratio, 3),
                     cum = round(cum_explained_variance_ratio, 3)))

  rownames( x ) <- c( 'Explained variance',
                      'Standard deviations',
                      'Proportion of variance',
                      'Cumulative proportion')

  colnames( x ) <- paste(rep('PC', length(object$sdev)), 1:length(object$sdev), sep = "")

  x <- as.matrix(x)

  return( x )
}