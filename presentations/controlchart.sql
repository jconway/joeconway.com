/*
 * controlchart.sql
 *
 * Example PL/R support for SPC control charts
 *
 * Joe Conway <mail@joeconway.com>
 * Copyright (c) 2003-2010, Joe Conway
 * ALL RIGHTS RESERVED;
 *
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without a written agreement
 * is hereby granted, provided that the above copyright notice and this
 * paragraph and the following two paragraphs appear in all copies.
 *
 * IN NO EVENT SHALL THE AUTHOR OR DISTRIBUTORS BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING
 * LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS
 * DOCUMENTATION, EVEN IF THE AUTHOR OR DISTRIBUTORS HAVE BEEN ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * THE AUTHOR AND DISTRIBUTORS SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE AUTHOR AND DISTRIBUTORS HAS NO OBLIGATIONS TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 *
 */


-- table for auto-loaded plr functions
CREATE TABLE plr_modules (
  modseq int4,
  modsrc text
);

CREATE INDEX plr_modules_idx1 ON plr_modules(modseq);
DELETE FROM plr_modules WHERE modseq = 101;
-- insert the control chart function
DELETE FROM plr_modules WHERE modseq = 101;
INSERT INTO plr_modules
  VALUES (101, '
controlChart <- function(xdata, ssize, CLnumGroups = 0)
{
    if (!is.vector(xdata))
        stop("Data must be a vector") 

    if (!is.numeric(xdata))
        stop("Data vector must be numeric") 

    xdatalen <- length(xdata)
    if (xdatalen < ssize)
        stop("Data vector must be greater than or equal to sample size") 

    xdataresid <- xdatalen %% ssize 
    newxdatalen <- xdatalen - xdataresid 
    if (xdataresid != 0)
        xdata <- xdata[1:newxdatalen] 

    if (ssize < 1 | ssize > 10)
    {
        stop("Sample size must be in the range of 1 to 10") 
    }
    else if (ssize > 1 & ssize < 11)
    {
        # Xbar/R factors
        ng <- c(2:10) 
        D3 <- c(0,0,0,0,0,0.08,0.14,0.18,0.22) 
        D4 <- c(3.27,2.57,2.28,2.11,2.00,1.92,1.86,1.82,1.78) 
        A2 <- c(1.88,1.02,0.73,0.58,0.48,0.42,0.37,0.34,0.31) 
        d2 <- c(1.13,1.69,2.06,2.33,2.53,2.70,2.85,2.97,3.08) 
        v <- data.frame(ng, D3, D4, A2, d2) 

        # put into sample groups
        m <- matrix(xdata, ncol = ssize, byrow = TRUE) 

        # number of groups
        numgroups <- nrow(m)

        # Adjust number of points used to calculate control limits.
        if (numgroups < CLnumGroups | CLnumGroups == 0)
            CLnumGroups = numgroups

        # range for each group
        r <- apply(m, 1, range) 
        r <- r[2,] - r[1,] 

        # Rbar
        rb <- mean(r[1:CLnumGroups]) 
        rb <- rep(rb, numgroups) 

        # R UCL and LCL
        rucl <- v$D4[match(ssize,v$ng) + 1] * rb 
        rlcl <- v$D3[match(ssize,v$ng) + 1] * rb 

        # Xbar
        xb <- apply(m, 1, mean) 

        # Xbarbar
        xbb <- mean(xb[1:numgroups]) 
        xbb <- rep(xbb, numgroups) 

        # X UCL and LCL
        xucl <- xbb + (v$A2[match(ssize,v$ng) + 1] * rb) 
        xlcl <- xbb - (v$A2[match(ssize,v$ng) + 1] * rb) 
    }
    else            #sample size is 1
    {
        m <- xdata 

        # number of groups
        numgroups <- length(m) 

        # Adjust number of points used to calculate control limits.
        if (numgroups < CLnumGroups | CLnumGroups == 0)
            CLnumGroups = numgroups

        # set range for each group to 0
        r <- rep(0, numgroups) 

        # Rbar
        rb <- rep(0, numgroups) 

        # R UCL and LCL
        rucl <- rep(0, numgroups) 
        rlcl <- rep(0, numgroups) 

        # Xbar is a copy of the individual data points
        xb <- m 

        # Xbarbar is mean over the data
        xbb <- mean(xb[1:CLnumGroups])
        xbb <- rep(xbb, numgroups) 

        # standard deviation over the data
        xsd <- sd(xb[1:CLnumGroups]) 

        # X UCL and LCL
        xucl <- xbb + 3 * xsd 
        xlcl <- xbb - 3 * xsd 
    }

    # geometric moving average
    if (numgroups > 1)
    {
        rg <- 0.2
        gma = c(xb[1])
        for(i in 2:numgroups)
            gma[i] = (rg * xb[i]) + ((1 - rg) * gma[i - 1]) 
    }
    else # checked above to be at least 1
    {
        gma <- c(xb[1])
    }

    # create a single dataframe with all the plot data
    controlChartSummary <- data.frame(1:numgroups, xb, xbb, xucl, xlcl, r, rb, rucl, rlcl, gma) 

    return(controlChartSummary) 
}
');

select reload_plr_modules();

create type control_chart_summary_type as (
    group_num int,
    xb float8,
    xbb float8,
    xucl float8,
    xlcl float8,
    r float8,
    rb float8,
    rucl float8,
    rlcl float8,
    gma float8
);


-- sql function for producing control charts (the graphs themselves)
-- controlchart(<sql> text,
--              <sample-size> int,
--              <CL-num-groups> int,
--              <cc-names> text[])
CREATE OR REPLACE FUNCTION controlchart(text, int, int, text[])
RETURNS SETOF control_chart_summary_type as '
  # check for correct number of graph file names
  #if (!is.na(arg4) & length(arg4) != 3)
  if (length(arg4) != 0 & length(arg4) != 3)
    stop("Missing graph file name(s)")

  # get the data

  sql <- paste("select id_val ",
               "from sample_numeric_data ",
               "where ia_id=''", arg1, "'' ",
               "order by pi_insp_dt", sep="")
  rs <- pg.spi.exec(sql)
  xdata <- rs[,1]

  # sample size
  ssize <- arg2

  # get control chart data
  cc <- controlChart(xdata, ssize, arg3)

  #if (!is.na(arg4)) {
  if (length(arg4) != 0) {

    # get the attribute name
    sql <- paste("select ia_attname as val ",
                 "from atts ",
                 "where ia_id=''", arg1, "''", sep="")
    attname <- pg.spi.exec(sql)

    # get number of sample groups
    numgroups <- length(cc$xb)

    # X Bar chart
    # set up the graphics device
    x11(display=":1")

    plotxrange <- range(c(1:numgroups))
    plotyrange <- range(cc$xb, cc$xucl, cc$xlcl)
    plotyrange[1] <- plotyrange[1] - (plotyrange[2] - plotyrange[1]) * 0.1
    plotyrange[2] <- plotyrange[2] + (plotyrange[2] - plotyrange[1]) * 0.1

    jpeg(file=arg4[1],
         width = 480,
         height = 480,
         pointsize = 10,
         quality = 75)
    par (ask = FALSE,
         lwd = 2,
         pch = 20,
         lty = 1,
         col = "blue",
         bg = "#F8F8F8")
    plot(c(1:numgroups),
         xlim = plotxrange,
         ylim = plotyrange,
         cc$xb, type = "b",
         xlab = "Sample Group",
         ylab = "Value")
    lines(c(1:numgroups), cc$xbb, lty = 1)
    lines(c(1:numgroups), cc$xucl, lty = 1)
    lines(c(1:numgroups), cc$xlcl, lty = 1)
    title(main = paste("X Bar", attname$val, sep = " - "))

    dev.off()

    # R chart
    # set up the graphics device
    x11(display=":1")

    plotxrange <- range(c(1:numgroups))
    plotyrange <- range(cc$r, cc$rucl, cc$rlcl)
    plotyrange[1] <- plotyrange[1] - (plotyrange[2] - plotyrange[1]) * 0.1
    plotyrange[2] <- plotyrange[2] + (plotyrange[2] - plotyrange[1]) * 0.1

    jpeg(file=arg4[2],
         width = 480,
         height = 480,
         pointsize = 10,
         quality = 75)
    par (ask = FALSE,
         lwd = 2,
         pch = 20,
         lty = 1,
         col = "blue",
         bg = "#F8F8F8")
    plot(c(1:numgroups),
         xlim = plotxrange,
         ylim = plotyrange,
         cc$r, type = "b",
         xlab = "Sample Group",
         ylab = "Value")

    lines(c(1:numgroups), cc$rb, lty = 1)
    lines(c(1:numgroups), cc$rucl, lty = 1)
    lines(c(1:numgroups), cc$rlcl, lty = 1)
    title(main = paste("Range", attname$val, sep=" - "))

    dev.off()

    # Geometric Moving Average chart
    # set up the graphics device
    x11(display=":1")

    plotxrange <- range(c(1:numgroups))
    plotyrange <- range(cc$gma)
    plotyrange[1] <- plotyrange[1] - (plotyrange[2] - plotyrange[1]) * 0.1
    plotyrange[2] <- plotyrange[2] + (plotyrange[2] - plotyrange[1]) * 0.1

    jpeg(file=arg4[3],
         width = 480,
         height = 480,
         pointsize = 10,
         quality = 75)
    par (ask = FALSE,
         lwd = 2,
         pch = 20,
         lty = 1,
         col = "blue",
         bg = "#F8F8F8")
    plot(c(1:numgroups),
         xlim = plotxrange,
         ylim = plotyrange,
         cc$gma, type = "b",
         xlab = "Sample Group",
         ylab = "Value")
    title(main = paste("GMA", attname$val, sep=" - "))

    dev.off()

    # adjust unix permissions so the web server can read our output
    system(paste("chmod 666 ", arg4[1], sep=""), intern = FALSE, ignore.stderr = TRUE)
    system(paste("chmod 666 ", arg4[2], sep=""), intern = FALSE, ignore.stderr = TRUE)
    system(paste("chmod 666 ", arg4[3], sep=""), intern = FALSE, ignore.stderr = TRUE)
  }

  return(cc)
' language 'plr';

select * from controlchart('G121XA34', 3, 0, null);
select * from controlchart('G121XA34', 3, 0, array['/tmp/xbar.jpg','/tmp/r.jpg','/tmp/gma.jpg']);
