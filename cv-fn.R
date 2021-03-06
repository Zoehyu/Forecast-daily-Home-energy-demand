require(glue)
require(dplyr)
require(doSNOW)

# create a list with information for all the models.
modelcv = function(
    y, # time series
    xreg = NULL,
    models,
    windowsize = 160,
    h = 12,
    numcvs = NULL,
    runtypes = c('sliding', 'expanding'),
    verbose = TRUE,
    numcores = 2, # set to 1 for easier troubleshooting.
    packages = c(), # add'l packages for parallel.
    ... # other args that will be passed to modeling functions.
){
    
    # calculating where to start is a bit tricky.
    #  first we calculate what the last training window will be (depends on forecast interval h)
    #  then we subtract the number of cvs from that to get our starting point
    lastwindow = (length(y) - h - windowsize + 1):(length(y) - h)
    startat = if(is.null(numcvs)){ 1 }  else { lastwindow[1] - numcvs + 1 }
    iterateoverstarts = startat:lastwindow[1]
    
    if(!is.null(numcvs) && windowsize + numcvs + h > length(y)) stop(glue('
       windowsize + numcvs + h ({windowsize} + {numcvs} + {h} = {windowsize + numcvs + h} exceeds number of observations ({length(y)})) 
    '))

    # build the list of CV info.
    dt = list()
    for(iwindowstart in iterateoverstarts){

        # expanding window.        
        if('expanding' %in% runtypes) for(imodel in models) if(is.null(imodel$enabled) || imodel$enabled){

            idt = list(
                train_from = 1,
                train_thru =(iwindowstart + windowsize - 1),
                test_from = (iwindowstart + windowsize),
                test_thru = (iwindowstart + windowsize + h - 1)
            )
            idt$train = y[idt$train_from:idt$train_thru]
            idt$test = y[idt$test_from:idt$test_thru]
            if(!is.null(xreg)) idt$xreg = xreg[idt$train_from:idt$train_thru, ]

            idt$model = imodel
            idt$windowtype = 'expanding'            

            dt[[length(dt) + 1]] <- idt
            rm(idt)

        }

        if('sliding' %in% runtypes) for(imodel in models) if(is.null(imodel$enabled) || imodel$enabled){

            idt = list(
                train_from = iwindowstart,
                train_thru =(iwindowstart + windowsize - 1),
                test_from = (iwindowstart + windowsize),
                test_thru = (iwindowstart + windowsize + h - 1)
            )
            
            idt$train = y[idt$train_from:idt$train_thru]
            idt$test = y[idt$test_from:idt$test_thru]
            if(!is.null(xreg)) idt$xreg = xreg[idt$train_from:idt$train_thru, ]
            
            idt$model = imodel
            idt$windowtype = 'sliding'

            dt[[length(dt) + 1]] <- idt
            rm(idt)

        }

    }

    # set up the function to use at each iteration.
    dofn = function(idt){

            im = idt$model$fit(y = idt$train, xreg = idt$xreg)
            h = length(idt$test)

            if(is.null(idt$model$forecast)) idt$model$forecast = function(m, h, ...) forecast(m, h)$mean
            if(is.null(idt$model$residuals)) idt$model$residuals = function(m) residuals(m)
            if(is.null(idt$model$bic)) idt$model$bic = function(m) BIC(m)

            data.frame(
                window = idt$windowtype,
                model = idt$model$name,
                train_from = idt$train_from,
                train_thru = idt$train_thru,
                test_from = idt$test_from,
                test_thru = idt$test_thru,
                bic = idt$model$bic(im), # more consinstenlty implemented than AICc,
                forecast_horizon = 1:h,
                forecasterr = as.numeric(idt$model$forecast(m = im, h = h, xreg = idt$xreg, y = idt$train)) - idt$test,
                modelerr = as.numeric(tail(idt$model$residuals(im), h))
            )        

    }

    # run the CVs in parallel.
    if(verbose) cat(glue('Running {length(dt)} CV models \n'))
    if(is.null(numcores) || numcores == 1){
        # if 1 core, just use lapply for easier troubleshooting.
        results = lapply(dt, dofn)
    } else {
        cat('\t in parallel')
        cl = makeSOCKcluster(numcores)
        registerDoSNOW(cl)
        results = tryCatch({
            foreach(
                i = dt, 
                .packages = c('forecast', 'vars', 'glue', packages),
                .options.snow = if(verbose) list(progress = function(n) if(n %% 10 == 0) cat("\rCV ", n, " of ", length(dt), " complete \n"))
            ) %dopar% dofn(i)
        # on error, stop the cluster.
        }, error = function(e){
            stopCluster(cl)
            stop(e)
        })
        stopCluster(cl)
    }

    # combine into a single data frame.
    results = bind_rows(results)
    
    return(list(
        results = results, 
        summary = results %>%
            group_by(model, window, forecast_horizon) %>% 
            summarize(
                cv_count = n(),
                mae_fit = mean(abs(modelerr)),
                mae_test = mean(abs(forecasterr)),
                rmse_fit = sqrt(mean(modelerr ** 2)),
                rmse_test = sqrt(mean(forecasterr ** 2)),
                mean_bic = mean(bic)
            ) %>%
            arrange(forecast_horizon, rmse_test)
    ))

}
