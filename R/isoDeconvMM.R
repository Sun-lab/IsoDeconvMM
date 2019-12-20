#' Title
#'  
#' \code{isodeconvMM} ... description
#' 
#' @param directory an optional character string denoting the path to the directory where all of the 
#' mix_files, pure_ref_files, fraglens_files, and bedfile are located.
#' @param mix_files a vector of the file names for the count files (in .txt formats) 
#' for the samples containing mixtures of cells (add more details)
#' @param pure_ref_files a data.frame or matrix where the first column is the file names for the 
#' count files (in .txt formats) for the pure reference cell type samples and the second column
#' contains the names of the pure cell type associated with each sample
#' @param fraglens_files a vector of the file names for the fragment length files. This data
#' should contain two columns, one for () and another for ()
#' @param bedfile name of the .bed file associated with the data
#' @param knownIsoforms character string for the name of an RData object. This RData object is a
#' list where each element of the list corresponds to a transcript cluster
#' and contains a matrix of 0s and 1s, where the rows correspond to exons and the columns correspond 
#' to isoforms. Instructions for creating such an RData object can be found in the (isoforms vignette)
#' @param discrim_genes vector of genes that are suspected to have differential gene expression 
#' (perhaps based on CuffLinks output)
#' @param readLen numeric value of the read length of the RNAseq experiment
#' @param lmax numeric value of the maximum fragment length of the experiment
#' @param eLenMin numeric value of the minimum value of effective length which allows for errors 
#' in the sequencing/mapping process
#' @param mix_names an optional vector of the desired nicknames of the mixture samples corresponding,
#' in the same order, to the mix_files list. If left as the defaul NULL value, the nicknames used
#' will be the names given in the mix_files minus the .txt extension
#' @param initPts an optional matrix of initial probability estimates for the cell composition
#' of the mixture samples to be used in the optimization procedure. The matrix should have k columns,
#' where k = number of pure cell types of interest. Each row corresponds to different combinations of 
#' initial probability values. The column names of the matrix must correspond to the pure cell type
#' names given in the second column of the pure_ref_files object (no particular ordering needed)
#' 
#' @return A list object with the following elements (...)
#'  
#' @importFrom stringr str_c str_remove
#' @export
isoDeconvMM = function(directory = NULL, mix_files, pure_ref_files, fraglens_files,
                       bedfile, knownIsoforms, discrim_genes, 
                       readLen, lmax = 600, eLenMin = 1, mix_names = NULL,
                       initPts = NULL){
  
  # Convert given arguments to alternative formats
  
  countData_mix = mix_files
  countData_pure = c(pure_ref_files[,1])
  cellTypes_pure = as.factor(c(pure_ref_files[,2]))
  cellTypes_pure_names = levels(cellTypes_pure)
  
  labels_pure = character(length(countData_pure))
  
  for(type in levels(cellTypes_pure)){
    locations = which(cellTypes == type)
    labels_type = cellTypes[locations]
    num_ref = length(labels_type)
    labels_ref = str_c(labels_type, "_ref", 1:num_ref)
    labels_pure[locations] = labels_ref
  }
  
  ## See comp_total_cts function after isodecov function
  pure_input = comp_total_cts(directory = directory, countData = countData_pure)
  
  mix_input = comp_total_cts(directory = directory, countData = countData_mix)
  
  fraglens_list = list()
  for(i in 1:length(fraglens_files)){
    if(is.null(directory)){
      # Use current working directory
      fraglens = read.table(fraglens_files[i])
    }else{
      fraglens = read.table(sprintf("%s/%s", directory, fraglens_files[i]), as.is = T)
    }
    
    if (ncol(fraglens) != 2) {
      stop(fraglens_files[i], " should have 2 columns for Freq and Len\n")
    }
    names(fraglens) = c("Freq", "Len")
    
    fraglens_list[[i]] = fraglens
  }
  
  files = list()
  
  for(i in 1:length(mix_files)){
    
    mix_counts = mix_input$counts_list[[i]]
    pure_counts = pure_input$counts_list
    
    countData = pure_counts
    countData[[(length(pure_counts)+1)]] = mix_counts
    
    total_cts = c(mix_input$total_cts[i], pure_input$total_cts)
    
    
    fragSizeFile = fraglens_list[[i]]
    
    files[[i]] = list(countData = countData, total_cts = total_cts,
                      fragSizeFile = fragSizeFile)
    
  }
  
  if(is.null(initPts)){
    initPts = matrix(1/length(cellTypes_pure_names), nrow = 1, ncol = length(cellTypes_pure_names))
  }else if(class(initPts = "matrix")){
    if(ncol(initPts) != length(cellTypes_pure_names)){
      stop("number of columns of initPts must be equal to the number of pure reference cell types")
    }
    if(!(colnames(initPts) %in% cellTypes_pure_names)){
      stop("colnames of initPts must match pure cell type names in pure_ref_files; see documentation for more details")
    }
    if(sum(initPts > 1) > 0 | sum(initPts < 0) > 0 | (nrow(initPts) > 1 & sum(rowSums(initPts) > 1) > 0)){
      stop("initPts specifies probabilities, which cannot be below 0 or above 1 or sum to more than 1")
    }
  }else{
    stop("initPts must be a matrix, see documentation for details")
  }
  
  # Re-arrange column order of initPts matrix to match order of cellTypes_pure_names
  initPts = initPts[,cellTypes_pure_names]
  
  #-------------------------------------------------------------------------------------------------------------------------------------------#
  # CHECKING Presence of Isoforms File:                                                                                                       #
  #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
  # IsoDeconv requires a list of known isoforms in order to model intra-sample heterogeneity. Stops program if file not present.              #
  #-------------------------------------------------------------------------------------------------------------------------------------------#
  
  if(!is.null(knownIsoforms)){
    assign("isoAll", get(load(knownIsoforms)))
  }else{
    stop("knownIsoforms list object must be present!")
  }
  
  # Load knownIsoforms .RData object:
  
  assign("isoAll", get(load(knownIsoforms)))
  
  # Alternative methods of loading knownIsoforms .RData object:
  
  # loadRData <- function(fileName){
  #   #loads an RData file, and returns it
  #   load(fileName)
  #   get(ls()[ls() != knownIsoforms]) # get(ls()[ls() != "fileName"])
  # }
  # 
  # isoAll = loadRData(knownIsoforms)
  
  # # Load the data, and store the name of the loaded object in x
  # x = load('data.Rsave')
  # # Get the object by its name
  # y = get(x)
  # # Remove the old object since you've stored it in y 
  # rm(x)
  
  # assign('newname', get(load('~/oldname.Rdata')))
  
  #-----------------------------------------------------------------------------#
  # ESTABLISHING CLUSTERS WITH HIGHEST LEVELS OF DISCRIMINATORY CAPABILITY      #
  #-----------------------------------------------------------------------------#
  
  #------------------ Identify Highly Discriminatory Clusters -------------------#
  
  # User inputs discrim_genes information
  # Find names of clusters that contain these discriminatory genes
  
  all_clusters = names(knownIsoforms)
  idx_clust_tmp = numeric(length(all_clusters))
  
  for(i in 1:length(knownIsoforms)){
    clust_genes = colnames(knownIsoforms[[i]])
    if(any(clust_genes %in% discrim_genes)){
      idx_clust_tmp[i] = 1
    }
  }
  
  idx_clust = which(idx_clust_tmp==1)
  discrim_clusters = unique(all_clusters[inx_clust])
  
  # Step 1
  
  final_geneMod = list()
  
  for(j in 1:length(files)){
    
    file = files[[i]]
    
    countData = file$countData
    total_cts = file$total_counts
    fragSizeFile = file$fragSizeFile
    
    labels = c(labels_pure, "mix")
    cellTypes = c(cellTypes_pure, "mix")
    
    # Call dev_compiled_geneMod function
    ## See R/isoDeconv_geneModel_revised.R for dev_compiled_geneMod() code
    fin_geneMod = dev_compiled_geneMod(countData=countData,labels = labels,total_cts = total_cts, 
                                       cellTypes=cellTypes, bedFile=bedFile,knownIsoforms=isoAll,
                                       fragSizeFile=fragSizeFile,readLen=readLen,lmax=lmax,
                                       eLenMin=eLenMin, discrim_clusters=discrim_clusters)
    final_geneMod[[j]] = fin_geneMod
  }
  
  # Step 2: Moved to before Step 1 
  
  # Step 3
  
  # Original code (before specifying discriminatory clusters before Step 1)
  # significant_geneMod = list()
  # 
  # for(j in 1:length(final_geneMod)){
  #   
  #   fin_geneMod = final_geneMod[[j]]
  #   
  #   indices2chk = which(names(fin_geneMod)!="Sample_Info")
  #   indices_tmp = NULL
  #   indices=NULL
  #   
  #   # Identify clusters to analyze further based on discrim_genes information
  #   indices_tmp = rep(0,length(fin_geneMod))
  #   for(i in indices2chk){
  #     infodf = fin_geneMod[[i]]$info
  #     genesi = unique(infodf$gene)
  #     genesi = unique(unlist(strsplit(x=genesi,split = ":")))
  #     if(any(genesi %in% discrim_genes)){indices_tmp[i]=1}
  #   }
  #   indices = which(indices_tmp==1)
  #   
  #   sig_geneMod = fin_geneMod[indices]
  #   sig_geneMod["Sample_Info"] = fin_geneMod["Sample_Info"]
  #   
  #   ## See R/rem_clust.R for rem_clust() code
  #   sig_geneMod = rem_clust(geneMod = sig_geneMod,co = 5,min_ind = 0)
  #   
  #   significant_geneMod[[j]] = sig_geneMod
  # }
  
  significant_geneMod = list()
  
  for(j in 1:length(final_geneMod)){
    
    fin_geneMod = final_geneMod[[j]]
    
    ## See R/rem_clust.R for rem_clust() code
    sig_geneMod = rem_clust(geneMod = sig_geneMod,co = 5,min_ind = 0)
    
    significant_geneMod[[j]] = sig_geneMod
  }
  
  # Step 4
  
  #-------------------------------------------------------------------#
  # EDIT TO GROUP CELL TYPES                                          #
  #-------------------------------------------------------------------#
  
  ## Add rds_exons object to each cluster list object
  
  modified_sig_geneMod = list()
  
  for(f in 1:length(significant_geneMod)){
    
    sig_geneMod = significant_geneMod[[f]]
    
    info_mat = sig_geneMod[["Sample_Info"]]
    cellTypes = unique(info_mat$Cell_Type)
    
    ctList = list()
    
    for(j in 1:length(cellTypes)){
      idx = which(info_mat$Cell_Type==cellTypes[j])
      ctList[[cellTypes[j]]] = list(samps = info_mat$Label[idx], tots = info_mat$Total[idx])
    }
    
    idx2consider = which(names(sig_geneMod)!="Sample_Info")
    for(k in idx2consider){
      for(l in 1:length(cellTypes)){
        samps2use = ctList[[l]]$samps
        tots      = ctList[[l]]$tots
        
        y_vecs  = paste("sig_geneMod[[k]]$y",samps2use,sep = "_")
        y_vecsc = paste(y_vecs,collapse = ",")
        nExon = eval(parse(text=sprintf("length(%s)",y_vecs[1])))
        textcmd = sprintf("matrix(c(%s),nrow=nExon,ncol=length(samps2use))",y_vecsc)
        expMat  = eval(parse(text=textcmd))
        
        totmg   = tots - colSums(expMat)
        expMat2 = rbind(totmg,expMat)
        
        if(cellTypes[l]!="mix"){
          sig_geneMod[[k]][[cellTypes[l]]] = list(cellType=cellTypes[l],rds_exons=expMat2)
        } else {
          sig_geneMod[[k]][[cellTypes[l]]] = list(cellType=cellTypes[l],rds_exons_t=expMat2)
        }
        
      }
    }
    
    modified_sig_geneMod[[f]] = sig_geneMod
    
  }
  
  # Step 5
  
  #-----------------------------------------------------------#
  # CALL Pure Sample                                          #
  #-----------------------------------------------------------#
  
  pure_est = list()
  
  for(j in 1:length(modified_sig_geneMod)){
    
    sig_geneMod = modified_sig_geneMod[[j]]
    
    if(j == 1){
      
      # Only need to calcuate the pure sample parameters once
      
      sim.out = sig_geneMod[which(names(sig_geneMod)!="Sample_Info")]
      
      # Clusters with single isoforms: 
      # EXCLUDE THEM FOR THE MOMENT!
      dim_mat = matrix(0,nrow=length(sim.out),ncol=2)
      excl_clust = c()
      excl_clust2 = c()
      
      for(i in 1:(length(sim.out))){ 
        dim_mat[i,] = dim(sim.out[[i]][["X"]])
        
        if(all(dim_mat[i,]==c(1,1))){
          excl_clust = c(excl_clust,i)
        }
        if(dim_mat[i,2] == 1){
          excl_clust2 = c(excl_clust2,i)
        }
      }
      
      excl_clust_union = union(excl_clust,excl_clust2)
      if(length(excl_clust_union)>0){
        sim.new = sim.out[-c(excl_clust_union)]
      } else {
        sim.new = sim.out
      }
      
      # Optimize the Pure Sample Functions:
      ## See R/Production_Functions_PureSamp.R for Pure.apply.fun() code
      tmp.data = Pure.apply.fun(data.list = sim.new, cellTypes = cellTypes_pure, corr_co = 1)
      
      pure_est[[j]] = tmp.data
      
    }else{
      
      tmp_j = sig_geneMod
      # Share calculated pure sample paramters with other list elements associated with mixtures samples
      for(clust in names(sig_geneMod)){
        tmp_j[[clust]][["X.fin"]] = tmp.data[[clust]][["X.fin"]]
        tmp_j[[clust]][["X.prime"]] = tmp.data[[clust]][["X.prime"]]
        tmp_j[[clust]][["l_tilde"]] = tmp.data[[clust]][["l_tilde"]]
        tmp_j[[clust]][["I"]] = tmp.data[[clust]][["I"]]
        tmp_j[[clust]][["E"]] = tmp.data[[clust]][["E"]]
        tmp_j[[clust]][["alpha.est"]] = tmp.data[[clust]][["alpha.est"]]
        tmp_j[[clust]][["beta.est"]] = tmp.data[[clust]][["beta.est"]]
        for(ct in cellTypes_pure_names){
          tmp_j[[clust]][[ct]][["tau.hat"]] = tmp.data[[clust]][[ct]][["tau.hat"]]
          tmp_j[[clust]][[ct]][["gamma.hat"]] = tmp.data[[clust]][[ct]][["tau.hat"]]
        }
        
      }
      
      pure_est[[j]] = tmp_j
      
    }
    
  }
  
  # Step 6
  
  IsoDeconv_Output = list()
  
  for(i in 1:length(pure_est)){
    
    tmp.data = pure_est[[i]]
    
    #--------------------------------------------------------#
    # Establish input break ups                              #
    #--------------------------------------------------------#
    
    # Data Set Necessities:
    clust.start = 1
    clust.end = length(tmp.data)
    by.value = 15
    
    start.pts = seq(from = 1,to = clust.end,by = by.value)
    end.pts = c((start.pts[-1]-1),clust.end)
    
    cluster_output = list()
    for(m in 1:length(start.pts)){
      start.pt = start.pts[m]
      end.pt = end.pts[m]
      
      curr.clust.opt = tmp.data[c(start.pt:end.pt)]
      ## See R/Production_Functions_MixedSamp.R for STG.Updat_Cluster.All() code
      curr.clust.out = STG.Update_Cluster.All(all_data=curr.clust.opt, cellTypes = cellTypes_pure,
                                              optimType="nlminb", simple.Init=FALSE, initPts=c(0.5))
      
      cluster_output[[m]] = curr.clust.out
    }
    
    IsoDeconv_Output[[i]] = cluster_output
  }
  
  # Step 7
  
  #-----------------------------------------------------------------------#
  # Compile Files                                                         #
  #-----------------------------------------------------------------------#
  
  Final_Compiled_Output = list()
  
  for(j in 1:length(IsoDeconv_Output)){
    
    comp.out= NULL
    curr.clust.out = NULL
    
    #---- Set up new pattern ----#
    est.chunks = IsoDeconv_Output[[j]]
    
    message("File ", j)
    
    #---- Populate Output Dataset ----#
    comp.out = list()
    r = 1
    
    for(i in 1:length(est.chunks)){
      curr.clust.out = est.chunks[[i]]
      nl = length(curr.clust.out)
      for(m in 1:nl){
        comp.out[[r]]=curr.clust.out[[m]]
        r = r+1
      }
    }
    
    Final_Compiled_Output[[j]] = comp.out 
    
  }
  
  if(is.null(mix_names)){
    names(Final_Compiled_Output) = str_remove(mix_files, ".txt")
  }else{
    names(Final_Compiled_Output) = mix_names
  }
  
  
  return(Final_Compiled_Output)
  
  
}

# Helper functions

comp_total_cts = function(directory, countData){
  
  counts_list = list()
  total_cts = numeric(length(countData))
  
  for(i in 1:length(countData)){
    if(is.null(directory)){
      # Use current working directory
      countsi = read.table(countData[i], as.is = T)
    }else{
      countsi = read.table(sprintf("%s/%s", directory, countData[i]), as.is = T)
    }
    colnames(countsi) = c("count","exons")
    counts_list[[i]] = countsi
    counts_col = countsi[,1]
    total_cts[i] = sum(counts_col)
  }
  
  return(list(total_cts = total_cts, counts_list = counts_list))
}