output$RT_ECDF_MULT <- renderPlotly({
  req(length(DATA_RAW()) > 0)
  render_RT_ECDF_MULT()
})

get_data_RT_ECDF_MULT <- reactive({
  req(input$RTECDF.Aggr.Func || input$RTECDF.Aggr.Dim)
  input$RTECDF.Aggr.Refresh
  dsList <- subset(DATA_RAW(), algId %in% input$RTECDF.Aggr.Algs)
  
  if (!input$RTECDF.Aggr.Func) 
    dsList <- subset(dsList, funcId == input$Overall.Funcid)
  
  if (!input$RTECDF.Aggr.Dim) 
    dsList <- subset(dsList, DIM == input$Overall.Dim)
  
  if (length(dsList) <= 1) {
    shinyjs::alert("This is an invalid configuration for this plot. \n
                     Please ensure that the dataset contains multiple functions / 
                     dimensions to aggregate over.")
    return(NULL)
  }
  
  isolate({
    targets <- RT_ECDF_MULTI_TABLE()
  })
  
  # if (input$RTECDF.Aggr.Func && input$RTECDF.Aggr.Dim) {
  #   extract_funcId <- function(x) {
  #     substr(x, 0, stringi::stri_locate_all(x, fixed = ';')[[1]][[1]] - 1) 
  #   }
  #   extract_dim <- function(x) {
  #     substr(x, stringi::stri_locate_all(x, fixed = ';')[[1]][[1]] + 1, nchar(x)) 
  #   }
  #   targets <- melt(targets, id.vars = "funcId; DIM")
  #   targets[, funcId := extract_funcId(`funcId; DIM`), DIM := extract_dim(`funcId; DIM`)]
  # }
  # else if (input$RTECDF.Aggr.Func) {
  #   targets <- melt(targets, id.vars = "funcId")
  #   targets[, DIM := get_dim(dsList)]
  # }
  # else if (input$RTECDF.Aggr.Dim) {
  #   targets <- melt(targets, id.vars = "DIM")
  #   targets[, funcId := get_funcId(dsList)]
  # }
  # 
  # colnames(targets)[colnames(targets) == "value"] <- "target"
  generate_data.ECDF(dsList, targets, input$RTECDF.Aggr.Logx)
})

render_RT_ECDF_MULT <- reactive({
  withProgress({
    plot_general_data(get_data_RT_ECDF_MULT(), 'x', 'mean', 'line', 
                      scale.xlog = input$RTECDF.Aggr.Logx, 
                      x_title = "Function Evaluations",
                      y_title = "Proportion of (run, target, ...) pairs", 
                      show.legend = T)
    # 
    # Plot.RT.ECDF_Multi_Func(dsList, 
    #                         targets = targets, 
    #                         scale.xlog = input$RTECDF.Aggr.Logx)
  },
  message = "Creating plot")
})

output$RTECDF.Aggr.Download <- downloadHandler(
  filename = function() {
    eval(FIG_NAME_RT_ECDF_MULT)
  },
  content = function(file) {
    save_plotly(render_RT_ECDF_MULT(), file)
  },
  contentType = paste0('image/', input$RTECDF.Aggr.Format)
)

RT_ECDF_MULTI_TABLE <- reactiveVal(NULL)
trigger_renderDT <- reactiveVal(NULL)
proxy <- dataTableProxy('RT_GRID_GENERATED')

observe({
  alg <- input$RTECDF.Aggr.Algs
  funcid <- input$Overall.Funcid
  data <- DATA_RAW()
  dim <- input$Overall.Dim
  
  req(length(data) > 0)
  req(alg)
  req(funcid)
  req(dim)
  # req(data$suite != NEVERGRAD)

  dsList <- subset(data, algId %in% alg)
  req(length(dsList) > 0)

  if (!input$RTECDF.Aggr.Func) 
    dsList <- subset(dsList, funcId == input$Overall.Funcid)
  
  if (!input$RTECDF.Aggr.Dim) 
    dsList <- subset(dsList, DIM == input$Overall.Dim)
  
  if (length(dsList) == 0) return(NULL)
  
  targets <- get_ECDF_targets(dsList, input$RTECDF.Aggr.Target_type, input$RTECDF.Aggr.Target_number)
  
  RT_ECDF_MULTI_TABLE(targets) # add values to `RT_ECDF_MULTI_TABLE`
  trigger_renderDT(rnorm(1))
})

output$RT_GRID_GENERATED <- DT::renderDataTable({
  req(length(DATA_RAW()) > 0)
  trigger_renderDT()
  isolate({RT_ECDF_MULTI_TABLE()})
  }, 
  editable = TRUE, 
  rownames = FALSE,
  options = list(
    pageLength = 10, 
    lengthMenu = c(5, 10, 25, -1), 
    scrollX = T, 
    server = T,
    columnDefs = list(
      list(
        className = 'dt-right', targets = "_all"
      )
    )
  ),
  filter = 'top'
)

observeEvent(input$RT_GRID_GENERATED_cell_edit, {
  info <- input$RT_GRID_GENERATED_cell_edit
  i <- info$row
  j <- info$col + 1
  v <- info$value
  
  suppressWarnings({
    df <- RT_ECDF_MULTI_TABLE()
    set(df, i, j, coerceValue(v, as.numeric(df[i, ..j])))
    RT_ECDF_MULTI_TABLE(df)
  })
  replaceData(proxy, RT_ECDF_MULTI_TABLE(), 
              resetPaging = FALSE, rownames = FALSE)
})

observeEvent(input$RTECDF.Aggr.Table.Upload, {
  if (!is.null(input$RTECDF.Aggr.Table.Upload)) {
    df <- read.csv2(input$RTECDF.Aggr.Table.Upload$datapath, header = T, row.names = F) %>% 
      as.data.table
    
    if (ncol(df) == ncol(RT_ECDF_MULTI_TABLE())) {
      RT_ECDF_MULTI_TABLE(df)
      replaceData(proxy, RT_ECDF_MULTI_TABLE(), 
                  resetPaging = FALSE, 
                  rownames = FALSE)
    } else {
      RT_ECDF_MULTI_TABLE(df)
      trigger_renderDT(rnorm(1))
    }
  } else
    NULL
})

output$RTECDF.Aggr.Table.Download <- downloadHandler(
  filename = 'Example_ECDF_TARGETS.csv',
  content = function(file) {
    write.csv2(RT_ECDF_MULTI_TABLE(), file, row.names = F)
  },
  contentType = "text/csv"
)

# The ECDF plots for the runtime ----------------

get_data_RT_ECDF_Single <- reactive({
  ftargets <- as.numeric(format_FV(input$RTECDF.Single.Target))
  data <- subset(DATA(), algId %in% input$RTECDF.Single.Algs)
  generate_data.ECDF(data, ftargets, input$RTECDF.Single.Logx)
})

output$RT_ECDF <- renderPlotly({
  req(input$RTECDF.Single.Target)
  plot_general_data(get_data_RT_ECDF_Single(), 'x', 'mean', 'line', 
                    x_title = "Function Evaluations",
                    y_title = "Proportion of runs", scale.xlog = input$RTECDF.Single.Logx, show.legend = T)
  # ftargets <- as.numeric(format_FV(input$RTECDF.Single.Target))
  # data <- subset(DATA(), algId %in% input$RTECDF.Single.Algs)
  # Plot.RT.ECDF_Per_Target(data, ftargets, scale.xlog = input$RTECDF.Single.Logx)
})

output$RT_GRID <- renderPrint({
  req(input$RTECDF.Multi.Min, input$RTECDF.Multi.Max, input$RTECDF.Multi.Step)

  fstart <- format_FV(input$RTECDF.Multi.Min) %>% as.numeric
  fstop <- format_FV(input$RTECDF.Multi.Max) %>% as.numeric
  fstep <- format_FV(input$RTECDF.Multi.Step) %>% as.numeric

  req(fstart <= fstop, fstep <= fstop - fstart)
  data <- DATA()
  fall <- get_funvals(data)

  cat(seq_FV(fall, fstart, fstop, by = fstep))
})

output$RT_ECDF_AGGR <- renderPlotly({
  render_RT_ECDF_AGGR()
})

output$RTECDF.Multi.Download <- downloadHandler(
  filename = function() {
    eval(FIG_NAME_RT_ECDF_AGGR)
  },
  content = function(file) {
    save_plotly(render_RT_ECDF_AGGR(), file)
  },
  contentType = paste0('image/', input$RTECDF.Multi.Format)
)

get_data_RT_ECDF_AGGR <- reactive({
  req(input$RTECDF.Multi.Min, input$RTECDF.Multi.Max, input$RTECDF.Multi.Step)
  fstart <- format_FV(input$RTECDF.Multi.Min) %>% as.numeric
  fstop <- format_FV(input$RTECDF.Multi.Max) %>% as.numeric
  fstep <- format_FV(input$RTECDF.Multi.Step) %>% as.numeric
  data <- subset(DATA(), algId %in% input$RTECDF.Multi.Algs)
  targets <- seq_FV(get_funvals(data), fstart, fstop, fstep)
  generate_data.ECDF(data, targets, input$RTECDF.Multi.Logx)
})

render_RT_ECDF_AGGR <- reactive({
  withProgress({
  
    plot_general_data(get_data_RT_ECDF_AGGR(), 'x', 'mean', 'line', 
                      x_title = "Function Evaluations",
                      y_title = "Proportion of (run, target) pairs", 
                      scale.xlog = input$RTECDF.Multi.Logx, show.legend = T)
  
  # Plot.RT.ECDF_Single_Func(
  #   data, fstart, fstop, fstep,
  #   scale.xlog = input$RTECDF.Multi.Logx
  # )
  },
  message = "Creating plot")
})

# evaluation rake of all courses
output$RT_AUC <- renderPlotly({
  render_RT_AUC()
})

output$RTECDF.AUC.Download <- downloadHandler(
  filename = function() {
    eval(FIG_NAME_RT_AUC)
  },
  content = function(file) {
    save_plotly(render_RT_AUC(), file)
  },
  contentType = paste0('image/', input$RTECDF.AUC.Format)
)

get_data_RT_AUC <- reactive({
  req(input$RTECDF.AUC.Min, input$RTECDF.AUC.Max, input$RTECDF.AUC.Step)
  
  fstart <- format_FV(input$RTECDF.AUC.Min) %>% as.numeric
  fstop <- format_FV(input$RTECDF.AUC.Max) %>% as.numeric
  fstep <- format_FV(input$RTECDF.AUC.Step) %>% as.numeric
  data <- subset(DATA(), algId %in% input$RTECDF.AUC.Algs)
  targets <- seq_FV(get_funvals(data), fstart, fstop, fstep, length.out = 10)
  generate_data.AUC(data, targets)
})

render_RT_AUC <- reactive({
  # req(input$RTECDF.AUC.Min, input$RTECDF.AUC.Max, input$RTECDF.AUC.Step)
  # 
  # fstart <- format_FV(input$RTECDF.AUC.Min) %>% as.numeric
  # fstop <- format_FV(input$RTECDF.AUC.Max) %>% as.numeric
  # fstep <- format_FV(input$RTECDF.AUC.Step) %>% as.numeric
  # data <- subset(DATA(), algId %in% input$RTECDF.AUC.Algs)
  # 
  # Plot.RT.ECDF_AUC(
  #   data, fstart, fstop, fstep, fval_formatter = format_FV
  # )
  plot_general_data(get_data_RT_AUC(), 'x', 'AUC', 'radar')
})
