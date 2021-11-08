library(caret)
library(factoextra)
library(boot)
library(plotmo)

brazil<-load("~/Brazil_data_census.Rdata")
source("~/permtestPCA.R") # load permutation test function code

brazil$X<-NULL          #remove X
brazil$UF<-NULL         #remove UF
brazil$NOMEMUN<-NULL    #remove NOMENUM
brazil$R1040<-log(brazil$R1040) #log of R1040
brazil$RDPC<-log(brazil$RDPC)   #log of RDPC
brazil$Estados<-as.factor(brazil$Estados) #change to factor
brazil$Region<-as.factor(brazil$Region)   

#Split data
set.seed(400)
random_list<-sample(4500,4500, replace=FALSE) #create RNG list
predData<-brazil[random_list[1:10],]          #prediction sample
trainData<-brazil[random_list[11:3602],]      #train sample
testData<-brazil[random_list[3603:4500],]     #test sample

trainData$CODMUN6<-NULL   #remove CODNUM6
testData$CODMUN6<-NULL
predData$CODMUN6<-NULL

#LASSO using 10-fold cv
fitControl <- trainControl(method = "repeatedcv", number = 10, repeats = 1, verboseIter = TRUE)
set.seed(400)
lasso <- train(R1040 ~ .,
               trainData,
               preProcess = c("center", "scale"),
               method = 'glmnet',
               tuneGrid = expand.grid(alpha = 1,
                                      lambda = seq(0, 0.5, length =2000)),
               trControl = fitControl
)
plot_glmnet(lasso$finalModel, label=10) #coefficient path plot
plot(varImp(lasso, scale = TRUE))       #variable importance based on magnitude

#LASSO in-sample prediction
predicttrain <- predict(lasso, trainData)
expr1040train<-exp(trainData$R1040)       #back-transform for evaluation
exppredtrain<-exp(predicttrain)          
rmselassotrain<-data.frame(
  RMSE = RMSE(exppredtrain, expr1040train)
)                                         #RMSE of in-sample prediction

#LASSO out-of-sample prediction
predicttest <- predict(lasso, testData)
expr1040test<-exp(testData$R1040)         #back-transform for evaluation
exppredtest<-exp(predicttest)
rmselassotest<-data.frame(
  RMSE = RMSE(exppredtest, expr1040test)
)                                         #RMSE of out-of-sample prediction

#PCA
fitpca <- princomp(trainData[,c(-1,-11,-28)], cor = TRUE, scores = T)
summary(fitpca)
screeplot(fitpca, main="") #screeplot
print(summary(fitpca, loadings = TRUE, cutoff = 0.25), digits = 2) #check loadings
perm_range <- permtestPCA(trainData[,c(-1,-11,-28)])  #Permutation test  

#Bootstrap for PCA
my_boot_pca <- function(x, ind){
  res <- princomp(x[ind, ], cor = TRUE)
  return(res$sdev^2)
}
# Run bootstrap, in this code for PC4 
fit.boot  <- boot(data = trainData[,c(-1,-11,-28)], statistic = my_boot_pca, R = 1000)
eigs.boot <- fit.boot$t         # Store the R x p matrix with eigenvalues
par(mar = c(5, 4, 4, 1) + 0.1)
# histogram, code is same all PC's, only need to change the value 4
hist(eigs.boot[, 4], xlab = "Eigenvalue 4", las = 1, col = "blue", 
     main = "Bootstrap Confidence Interval", breaks = 20, 
     border = "white")
perc.alpha <- quantile(eigs.boot[, 4], c(0.025, 1 - 0.025) )
abline(v = perc.alpha, col = "green", lwd = 2)
abline(v = fitpca$sdev[4]^2, col = "red", lwd = 2)

#Biplot
fviz_pca_biplot(fitpca,
                label ="var",
                col.var = "gray26",
                geom.ind = "point",
                col.ind = trainData$Region,
                pointshape = 19, pointsize = 2, alpha.ind=0.5,
                palette = "jco", repel = TRUE, legend.title = "Regions") +xlim(-12, 12) + ylim (-12, 2)

#PCA linear regression using caret, select 4 components
fit2 <- train(R1040~.-Estados -Region, 
              method = "lm", 
              preProcess = "pca", 
              data = trainData, 
              trControl = trainControl(preProcOptions = list(pcaComp = 4)))
summary(fit2)

#PCA in-sample prediction
train_set.pca <- predict(fit2, trainData) 
exp.pca.train<-exp(train_set.pca)    #back-transform for evaluation
rmsepcatrain<-data.frame(
  RMSE = RMSE(exp.pca.train, expr1040train)
)

#PCA out-of-sample prediction
test_set.pca = predict(fit2, testData)
exp.pca.test<-exp(test_set.pca)     #back-transform for evaluation
rmsepcatest<-data.frame(
  RMSE = RMSE(exp.pca.test, expr1040test)
)

#Combine RMSE of LASSO and PCA in one 
eval<-cbind(rmselassotrain, rmselassotest, rmsepcatrain, rmsepcatest)
colnames(eval)<-c("LASSO Train", "LASSO Test", "PCA Train", "PCA Test")
eval

# Prediction for 10 municipalities
munlasso<- predict(lasso, predData)
munpca<- predict(fit2, predData)
predeval<-cbind(exp(munlasso), exp(munpca), exp(predData$R1040)) #back-transform
colnames(predeval)<-c("LASSO", "PCA", "Actual")
predeval<-round(predeval, digits = 2)
predeval[order(predeval[,3]),]
