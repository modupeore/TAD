<?php				
	session_start();
	require_once('all_fns.php');
	texpression(); 
?>
<?PHP
	//Database Attributes
	$table = "vw_sampleinfo";
?>

<div class="menu">TransAtlasDB Samples - Expression Information</div>
	<table width=80%><tr><td width="280pt">
	<div class="metamenu"><a href="expression.php">Gene Expression Summary</a></div>
	<div class="metactive"><a href="fragmentpkm.php">Samples-Gene Expression</a></div>
	<br><br><br></td><td>
	<div class="dift">
		<p>View expression (FPKM) summaries of samples and genes.<br>
		This provides a tab-delimited ".txt" file to easily compare the genes FPKM values across different samples.</p>

<?php
	@$species=$_GET['organism'];

	if(isset($species)){
		$query="SELECT sampleid FROM $table where organism='$species' order by sampleid"; 
	}else{ $query ="SELECT sampleid FROM $table where organism is null order by tissue"; }
	
	if (!empty($_REQUEST['salute'])) {
		$_SESSION[$table]['tissue'] = $_POST['tissue'];
		$_SESSION[$table]['organism'] = $_POST['organism'];
		$_SESSION[$table]['search'] = $_POST['search'];
	}
?>

  <div class="question">
  <form action="" method="post">
    <p class="pages"><span>Select Organism: </span>
    <select name="organism" onchange="reload(this.form)">
		<option value="" selected disabled >Select Organism</option>
		<?php
			foreach ($db_conn->query("select distinct organism from $table") as $row) {
				if($row["organism"]==@$species){ echo "<option selected value='$row[organism]'>$row[organism]</option><br>"; }
				else { echo '<option value="'.$row['organism'].'">'. $row['organism'].'</option>';}
			}
		?>
	</select></p>

    <p class="pages"><span>Specify your gene name: </span>
	<?php
		if (!empty($_SESSION[$table]['search'])) {
		  echo '<input type="text" name="search" id="genename" size="35" value="' .$_SESSION[$table]['search']. '"/></p>';
		} else {
		  echo '<input type="text" name="search" id="genename" size="35" placeholder="Enter Gene Name(s)" /></p>';
		}
	?>
	
	<p class="pages"><span>Libraries of interest: </span>
	<select name="tissue[]" id="tissue" size=3 multiple="multiple">
		<option value="" selected disabled >Select Tissue(s)</option>
		<?php
			foreach ($db_conn->query($query) as $row) {
				echo "<option value='$row[sampleid]'>$row[sampleid]</option>";
			}
		?>
		</select></p>
<center><input type="submit" name="salute" value="View Results"></center>
</form>
</div>
  </td></tr></table>

<?php
	if (!empty($_POST['salute'])) {
		echo '<div class="menu">Results</div><div class="xtra">';
		$queryforoutput = "yes";
		$output = "OUTPUT/avgfpkm_".$explodedate.".txt";
		if (!empty($_POST['tissue'])) { foreach ($_POST["tissue"] as $tissue){ $tissues .= $tissue. ","; } $tissues = rtrim($tissues,","); }
		if (!empty($_POST['search'])) { $genenames = rtrim($_POST['search'],","); }
		
		if ((!empty($_POST['tissue'])) && (!empty($_POST['organism'])) && (!empty($_POST['search']))) {          
			$pquery = "perl $basepath/tad-export.pl -w -db2data -genexp -species '$_POST[organism]' --gene '".strtoupper("$genenames")."' --samples '$tissues' -o $output";
		} elseif ((!empty($_POST['tissue'])) && (!empty($_POST['organism']))) {          
			$pquery = "perl $basepath/tad-export.pl -w -db2data -genexp -species '$_POST[organism]' --samples '$tissues' -o $output";
		} elseif ((!empty($_POST['search'])) && (!empty($_POST['organism']))) {          
			$pquery = "perl $basepath/tad-export.pl -w -db2data -genexp -species '$_POST[organism]' --gene '".strtoupper("$genenames")."' -o $output";
		} elseif (!empty($_POST['organism'])) {          
			$pquery = "perl $basepath/tad-export.pl -w -db2data -genexp -species '$_POST[organism]' -o $output";
		}else {
			$queryforoutput = "no";
			echo "<center>Forgot something ?</center>";
		}
		//print $pquery;
		if ($queryforoutput == "yes") {
			$rquery = shell_exec($pquery);
			if (file_exists($output)){
				echo '<form action="' . $phpscript . '" method="post">';
				echo '<p class="gened">Download the results below. ';
				$newbrowser = "results.php?file=$output&name=genes-stats.txt";
				echo '<input type="button" class="browser" value="Download Results" onclick="window.open(\''. $newbrowser .'\')"></p>';
				echo '</form>';
	
				// Get Tab delimted text from file
				$handle = fopen($output, "r");
				$contents = fread($handle, filesize($output)-1);
				fclose($handle);
				// Start building the HTML file
				print(tabs_to_table($contents));
			} else {
				echo '<center>No result based on search criteria.</center>';
			}
		}
	}
?>
  </div>
<?php
  $db_conn->close();
?>

<!-- <a class="back-to-top" style="display: inline;" href="#"><img src="images/backtotop.png" alt="Back To Top" width="45" height="45"></a>
<script src=”//ajax.googleapis.com/ajax/libs/jquery/1.11.0/jquery.min.js”></script>
    <script>
      jQuery(document).ready(function() {
        var offset = 250;
        var duration = 300;
        jQuery(window).scroll(function() {
          if (jQuery(this).scrollTop() > offset) {
            jQuery(‘.back-to-top’).fadeIn(duration);
          } else {
            jQuery(‘.back-to-top’).fadeOut(duration);
          }
        });
 
        jQuery(‘.back-to-top’).click(function(event) {
          event.preventDefault();
          jQuery(‘html, body’).animate({scrollTop: 0}, duration);
          return false;
        }) 
      });
    </script>-->
</body>
</html>
