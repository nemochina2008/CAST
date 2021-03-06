#' Forward feature selection
#' @description A simple forward feature selection algorithm
#' @param predictors see \code{\link{train}}
#' @param response see \code{\link{train}}
#' @param method see \code{\link{train}}
#' @param metric see \code{\link{train}}
#' @param maximize see \code{\link{train}}
#' @param withinSE Logical Models are only selected if they are better than the
#' currently best models Standard error
#' @param trControl see \code{\link{train}}
#' @param tuneLength see \code{\link{train}}
#' @param tuneGrid see \code{\link{train}}
#' @param seed A random number used for model training
#' @param numeric Number of cores for parallel processing
#' @param ... arguments passed to the classification or regression routine
#' (such as randomForest). Errors will occur if values for tuning parameters are
#' passed here.
#' @return A list of class train. Beside of the usual train content
#' the object contains the vector "selectedvars" and "selectedvars_perf"
#' that give the order of the best variables selected as well as their corresponding
#' performance (starting from the first two variables). It also contains "perf_all"
#' that gives the performance of all model runs.
#' @details Models with two predictors are first trained using all possible
#' pairs of predictor variables. The best model of these initial models is kept.
#' On the basis of this best model the predictor variables are iteratively
#' increased and each of the remaining variables is tested for its improvement
#' of the currently best model. The process stops if none of the remaining
#' variables increases the model performance when added to the current best model.
#'
#' The internal cross validation can be run in parallel. See information
#' on parallel processing of carets train functions for details.
#'
#' Using withinSE will favour models with less variables and
#' probably shorten the calculation time
#'
#' @note This validation is particulary suitable for
#' leave-location-out cross validations where variable selection
#' MUST be based on the performance of the model on the hold out station.

#' @author Hanna Meyer
#' @seealso \code{\link{train}},
#' \code{\link{trainControl}},\code{\link{CreateSpacetimeFolds}}
#' @examples
#'  \dontrun{
#' data(iris)
#' ffsmodel <- ffs(iris[,1:4],iris$Species)
#' ffsmodel$selectedvars
#' ffsmodel$selectedvars_perf
#' }
#'
#' # or perform model with target-oriented validation (LLO CV)
#' #the example is taken from the GSIF package and is described
#' #in Gasch et al. (2015). The ffs approach for this dataset is described in
#' #Meyer et al. (submitted to Environmental Modelling and Software).
#' Due to high computation time needed, only a small and thus not robust example
#' is shown here. Run it in parallel on 3 cores:
#'
#' require(doParallel)
#' cl <- makeCluster(3)
#' registerDoParallel(cl)
#'
#' dat <- get(load(system.file("extdata","Cookfarm.RData",package="CAST")))
#' trainDat <- dat[createDataPartition(dat$VW, p = 0.001,list=FALSE),]
#' indices <- CreateSpacetimeFolds(trainDat,spacevar = "SOURCEID")
#' predictors <- c("DEM","TWI","NDRE.M","Bt","BLD","PHI","Precip_cum","cdayt")
#' ffsmodel <- ffs(trainDat[,predictors],trainDat$VW,method="rf",
#' trControl=trainControl(method="cv",index=indices$index,indexOut=indices$indexOut),
#' tuneLength=1)
#'
#' stopCluster(cl)
#'
#' @export ffs
#' @aliases ffs

ffs <- function (predictors,
                 response,
                 method = "rf",
                 metric = ifelse(is.factor(response), "Accuracy", "RMSE"),
                 maximize = ifelse(metric == "RMSE", FALSE, TRUE),
                 withinSE = FALSE,
                 trControl = trainControl(),
                 tuneLength = 3,
                 tuneGrid = NULL,
                 seed = sample(1:1000, 1),
                 ...){
  require(caret)

  n <- length(names(predictors))
  acc <- 0
  perf_all <- list()
  if(maximize) evalfunc <- function(x){max(x,na.rm=T)}
  if(!maximize) evalfunc <- function(x){min(x,na.rm=T)}
  isBetter <- function (actmodelperf,bestmodelperf,
                        bestmodelperfSE=NULL,
                        maximization=FALSE,
                        withinSE=FALSE){
    if(withinSE){
      result <- ifelse (!maximization, actmodelperf < bestmodelperf-bestmodelperfSE,
                        actmodelperf > bestmodelperf+bestmodelperfSE)
    }else{
      result <- ifelse (!maximization, actmodelperf < bestmodelperf,
                        actmodelperf > bestmodelperf)
    }
    return(result)
  }
  #### chose initial best model from all combinations of two variables
  twogrid <- t(data.frame(combn(names(predictors),2)))
  for (i in 1:nrow(twogrid)){
    set.seed(seed)
    model <- train(predictors[,twogrid[i,]],
                   response,
                   method=method,
                   trControl=trControl,
                   tuneLength = tuneLength,
                   tuneGrid = tuneGrid)
    ### compare the model with the currently best model
    actmodelperf <- evalfunc(model$results[,names(model$results)==metric])
      actmodelperfSE <- Rsenal::se(
        sapply(unique(model$resample$Resample),
               FUN=function(x){mean(model$resample[model$resample$Resample==x,
                                                   metric])}))
    if (i == 1){
      bestmodelperf <- actmodelperf
      bestmodelperfSE <- actmodelperfSE
      bestmodel <- model
    } else{
      if (isBetter(actmodelperf,bestmodelperf,maximization=maximize,withinSE=FALSE)){
        bestmodelperf <- actmodelperf
        if(withinSE){
          bestmodelperfSE <- actmodelperfSE
        }
        bestmodel <- model
      }
    }
    acc <- acc+1
    perf_all[[acc]] <- list(
      model$finalModel$xNames,
      actmodelperf,actmodelperfSE)
    names(perf_all[[acc]]) <- c("variables",metric,"SE")
    print(paste0("maxmimum number of models that still need to be trained: ",
                 2*(n-1)^2/2-acc))
  }
  #### increase the number of predictors by one (try all combinations)
  #and test if model performance increases
  selectedvars <- names(bestmodel$trainingData)[-which(
    names(bestmodel$trainingData)==".outcome")]
  if (maximize){
    selectedvars_perf <- max(bestmodel$results[,metric])
  } else{
    selectedvars_perf <- min(bestmodel$results[,metric])
  }
  print(paste0(paste0("vars selected: ",paste(selectedvars, collapse = ',')),
               " with ",metric," ",round(selectedvars_perf,3)))
  for (k in 1:(length(names(predictors))-2)){
    startvars <- names(bestmodel$trainingData)[-which(
      names(bestmodel$trainingData)==".outcome")]
    nextvars <- names(predictors)[-which(
      names(predictors)%in%startvars)]
    if (length(startvars)<(k+1)){
      message(paste0("Note: No increase in performance found using more than ",
                     length(startvars), " variables"))
      bestmodel$selectedvars <- selectedvars
      bestmodel$selectedvars_perf <- selectedvars_perf[-length(selectedvars_perf)]
      names(perf_all) <- paste0("run_", 1:length(perf_all))
      bestmodel$perf_all <- perf_all
      return(bestmodel)
      break()
    }
    for (i in 1:length(nextvars)){
      set.seed(seed)
      model <- train(predictors[,c(startvars,nextvars[i])],
                     response,
                     method = method,
                     trControl = trControl,
                     tuneLength = tuneLength,
                     tuneGrid = tuneGrid)
      actmodelperf <- evalfunc(model$results[,names(model$results)==metric])
        actmodelperfSE <- Rsenal::se(
          sapply(unique(model$resample$Resample),
                 FUN=function(x){mean(model$resample[model$resample$Resample==x,
                                                     metric])}))
      if(isBetter(actmodelperf,bestmodelperf,bestmodelperfSE,
                  maximization=maximize,withinSE=withinSE)){
        bestmodelperf <- actmodelperf
          bestmodelperfSE <- actmodelperfSE
        bestmodel <- model
      }
      acc <- acc+1
      perf_all[[acc]] <- list(
        model$finalModel$xNames,
        actmodelperf,actmodelperfSE)
      names(perf_all[[acc]]) <- c("variables",metric,"SE")
      print(paste0("maxmimum number of models that still need to be trained: ",
                   2*(n-1)^2/2-acc))
    }
    selectedvars <- c(selectedvars,names(bestmodel$trainingData)[-which(
      names(bestmodel$trainingData)%in%c(".outcome",selectedvars))])
    if (maximize){
      selectedvars_perf <- c(selectedvars_perf,max(bestmodel$results[,metric]))
      print(paste0(paste0("vars selected: ",paste(selectedvars, collapse = ',')),
                   " with ", metric," ",round(max(bestmodel$results[,metric]),3)))
    }
    if (!maximize){
      selectedvars_perf <- c(selectedvars_perf,min(bestmodel$results[,metric]))
      print(paste0(paste0("vars selected: ",paste(selectedvars, collapse = ',')),
                   " with ",metric," ",round(min(bestmodel$results[,metric]),3)))
    }
  }
  bestmodel$selectedvars <- selectedvars
  bestmodel$selectedvars_perf <- selectedvars_perf
  names(perf_all) <- paste0("run_", 1:length(perf_all))
  bestmodel$perf_all <- perf_all
  return(bestmodel)
}
