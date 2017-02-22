#TransAtlasDB documentation

##Introduction

TransAtlasDB is an integrated database system from transcriptome analysis data. 

This is the GitHub repository for the documentation of the TransAtlasDB software.

If you like this repository, please click on the "Star" button on top of this page, to show appreciation to the repository maintainer. If you want to receive notifications on changes to this repository, please click the "Watch" button on top of this page.


##TransAtlasDB main package

The TransAtlasDB toolkit is written in Perl and can be run on diverse hardware systems where standard Perl modules and the Perl-DBD module are installed. The package consist of the following files:

- **INSTALL-tad.pL**: install TransAtlasDB system.

- **connect-tad.pL**: verify connection details or create connection details (used only when requested).

- **tad-import.pl**: import samples metadata and RNAseq data into the database. 

- **tad-interact.pl**: interactive interface to explore database content.

- **tad-export.pl**: view or export reports based on user-defined queries.

- **other folders**:
	* schema : contains the TransAtlasDB relational database schema.
	* example : contains sample files and templates.
	* lib : contains required Perl Modules.

Please click the menu items to navigate through this repository. If you have questions, comments and bug reports, please email me directly. Thank you very much for your help and support!

##TransAtlasDB installation
- Requirements:
	* Operating System :
		* Linux / Mac (tested and verified)

	* Databases :
		* MySQL
		* FastBit

	* Perl Module :
		* Perl-DBD module
- Quick Guide:
	* To install [with root priviledges]
	```
	INSTALL-tad.pl -password <mysql-password>
	```
Further details are provided at https://modupeore.github.io/TransAtlasDB/tutorial.html

---