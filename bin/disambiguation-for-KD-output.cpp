
#include <iostream>
#include <map>
#include <unordered_map>
#include <set>
#include <fstream>
#include <string>
#include <vector>
#include <algorithm>

#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <libgen.h>
#include <string.h>

#define INT long int

using namespace std;

const string progName = "disambiguation-for-KD-output";
string minConceptFreq0 = "3";
string minPosteriorProb0 = "0.95";
string method0 = "advanced";
int ignoreTargetIfNotInPairsData = 0;
int advancedDiscriminativeFeatsOnly = 1;
vector<string> externalCuisByPmidOpts;

INT totalNbDocs;

INT totalCases = 0;
INT totalAmbig = 0;
INT ambigFixed = 0;
INT totalDiscardedDueToNotInPairsData = 0;
INT uniqueTotalCases = 0;
INT uniqueSuccess = 0;
INT uniqueUnknownTarget = 0;
INT uniqueMethodNA = 0;
INT uniqueThrehsholdReject = 0;


int minFreqThresholdDone = 0;


void usage(ostream &out) {
  out << "\n";
  out << "Usage: ls <input files> | "<< progName<<" [options] <nb docs> <pairs stats file> <output dir>\n";
  out << "\n";
  out << "   Attempts to disambiguate groups of CUIs corresponding to the same term in the output\n";
  out << "   of the KD system. Reads input files from STDIN, requires the number of documents  <nb docs>\n";
  out << "   used to build the <pairs stats file> which contains the statistics (including joint\n";
  out << "   frequency) for every pair of non-ambiguous CUIs.";
  out << "\n";
  out << "  Main options:\n";
  out << "     -h print this help message\n";
  //  out << "     -m if used, <input 'mined' dir> contains subfolders 'articles' and 'abstracts'\n";
  //  out << "        and the data is read from there (use this to use KD output dir directly).\n";
  out << "     -r <reference file> use this reference file for converting the indexes in the\n";
  out << "        data files to actual CUIs. Typically <reference file> is\n";
  out << "        'umlsWordlist.WithIDs.txt'. A terms id corresponds to the line number\n";
  out << "        containing the CUI in the reference file.\n";
  //  out << "     -i Read a single .cuis file as input instead of <input 'mined' dir>\n";
  out << "     -f <min freq> min frequency of concept. Default: "<<minConceptFreq0<<".\n";
  out << "     -b <min posterior prob> min posterior NB prob for 'accepting' the predicted\n";
  out << "        disambiguated concept. Default: "<<minPosteriorProb0<<".\n";
  out << "     -a <method> where method is 'basic', 'NB', 'advanced'. Default: '"<<method0<<"'.\n";
  out << "     -d dismiss potential target if it has zero occurrences in the pairs data\n";
  out << "        (only for methods NB and advanced). CAUTION: this can cause errors.\n";
  out << "     -A use all features instead of 'discriminative features' only for the advanced\n";
  out << "        method. Unused with other methods.\n";
  out << "     -M multi methods: allows a list of values for -a, -f, -b and runs the process\n";
  out << "        for every combination of parameters values. Values separated by ':'.\n";
  out << "        This option is intended to reduce computation time due to loading\n";
  out << "     -e <file:colPMID:colCUIs:sep> external resource providing additional CUIs for\n";
  out << "        every document by PMID, , e.g. list of converted Mesh descriptors. This\n";
  out << "        option is supposed to be used if the <pairs stats file> is obtained using\n";
  out << "        the same external resource (typically converted Mesh descriptors).\n";
  out << "\n";
}


string strProp(INT nb, INT total) {
  char buff[100];
  sprintf(buff, "%.2f",(float) nb /(float) total * (float) 100);
  return string(buff);
}

void resetStatsCase() {
  totalCases = 0;
  totalAmbig = 0;
  ambigFixed = 0;
  totalDiscardedDueToNotInPairsData = 0;
  uniqueTotalCases = 0;
  uniqueSuccess = 0;
  uniqueUnknownTarget = 0;
  uniqueMethodNA = 0;
  uniqueThrehsholdReject = 0;
}


void createDirIfNeeded(const char *path) {
  struct stat sb;

  if (stat(path, &sb) != 0 || !S_ISDIR(sb.st_mode)) {
    if (mkdir(path, 0777) == -1) {
      cerr << "Error : cannot create dir '" << path <<"'"<< endl; 
    }
  }
}


vector<string> split(string s, char sep) {
  vector<string> res = vector<string>();
  int prevPos=0;
  int pos = s.find(sep, prevPos-prevPos);
  while (pos != string::npos) {
    //    cerr << "A split: s='"<<s<<"'; prev="<<prevPos<<"; pos="<<pos<<"; substr="<<s.substr(prevPos, pos-prevPos)<<endl;
    res.push_back(s.substr(prevPos, pos-prevPos));
    prevPos=pos+1;
    pos = s.find(sep,prevPos);
  }
  //  cerr << "B split: s='"<<s<<"'; prev="<<prevPos<<"; pos="<<pos<<"; substr="<<s.substr(prevPos)<<endl;
  res.push_back(s.substr(prevPos));
  //  cerr << "SIZE "<<res.size()<<endl;
  return res;
}


string join(vector<string> v, string sep) {
  string r ="";
  if (v.size()>0) {
    r = v[0];
    for (int i=1; i< v.size(); i++) {
      r += sep;
      r+=v[i];
    }
  }
  return r;
}


void jointMapAdd(unordered_map<string, unordered_map<string, INT>*> *jointFreq, string &cui1, string &cui2, INT jointFreqVal) {


  unordered_map<string, unordered_map<string, INT>*>::iterator it = jointFreq->find(cui1);
  unordered_map<string, INT> *submap;
  if (it != jointFreq->end()) {
    submap = it->second;
  } else {
    submap = new unordered_map<string, INT>();
    jointFreq->insert({cui1, submap});
  }
  submap->insert({ cui2, jointFreqVal });

}


unordered_map<INT, string> *readCuiRefFile(string filename) {

  unordered_map<INT, string> *m = new unordered_map<INT, string>();
  ifstream file(filename);
  if (!file) {
    cerr << "Error opening "<< filename << endl;
    exit(1);
  }
  INT id=0;
  string str; 
  while (getline(file, str)) {
    vector<string> cols = split(str,'\t');
    string cui = cols[0];
    m->insert({id, cui});
    id++;
  }
  file.close();
  return m;

}



unordered_map<string, vector<string>> *readExternalResource(string &filename, int colPMIDNo, int colCuisNo, char separator) {

  unordered_map<string, vector<string>> *m = new unordered_map<string, vector<string>>();
  colPMIDNo--;
  colCuisNo--;
  ifstream file(filename);
  if (!file) {
    cerr << "Error opening "<< filename << endl;
    exit(1);
  }
  string str; 
  int lineNo=1;
  while (getline(file, str)) {
    vector<string> cols = split(str,'\t');
    if ((cols.size()<=colPMIDNo) || (cols.size()<=colCuisNo)) {
      cerr << "Format error in '"<<filename<<"' line "<<lineNo<<": not enough columns" <<endl;
      exit(5);
    }
    string &pmid = cols[colPMIDNo];
    string &cuisStr= cols[colCuisNo];
    vector<string> cuis = split(cuisStr, separator);
    m->insert({pmid, cuis});
    lineNo++;
  }
  file.close();
  return m;

}



void readPairsData(string filename, unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq, int minFreq) {


  ifstream file(filename);
  if (!file) {
    cerr << "Error opening "<< filename << endl;
    exit(1);
  }

  
  string str; 
  getline(file, str); // skip header
  INT lineNo=1;

  while (getline(file, str)) {

    if (lineNo % 8192 == 0) {
      fprintf(stderr,"\r%ld",lineNo);
    }

    vector<string> cols = split(str,'\t');

    string cui1 = cols[0];
    string cui2 = cols[1];
    INT freqC1 = strtol(cols[2].c_str(), NULL,10);
    INT freqC2 = strtol(cols[3].c_str(), NULL,10);

    if ((freqC1 >= minFreq) && (freqC2 >= minFreq)) {
      INT jointFreqVal = strtol(cols[6].c_str(), NULL,10);
      uniFreq->insert({ cui1, freqC1 });
      uniFreq->insert({ cui2, freqC2 });
      jointMapAdd(jointFreq, cui1, cui2, jointFreqVal);
      jointMapAdd(jointFreq, cui2, cui1, jointFreqVal);
    }
    lineNo++;
  }
  file.close();
  cerr<<endl;

}



vector<string> disambiguateBasic(vector<string> &targets, unordered_map<string, INT> &features, int minConceptFreq, double minPosteriorProb, unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq) {
  
  int nbTargets = targets.size();
  uniqueTotalCases++;
  vector<string> res;
  INT *countMatches = (INT *) calloc(nbTargets, sizeof(INT));
  INT totalMatches = 0;
  
  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    unordered_map<string, INT>::iterator it = features.find(targets[targetNo]);
    if (it != features.end()) {
      countMatches[targetNo] += it->second;
      totalMatches += it->second;
    }
  }
  if (totalMatches == 0) {
    uniqueMethodNA++;
    free(countMatches);
    return res; //empty
  } else {
    int maxTargetNo = -1;
    double maxP = -1;
    for (int targetNo=0; targetNo<nbTargets; targetNo++) {
      INT c = countMatches[targetNo];
      double p = (double) c / (double) totalMatches;
      if (p > maxP) {
	maxTargetNo = targetNo;
	maxP = p;
      }
    }
    free(countMatches);
    if (maxP > minPosteriorProb) {
      uniqueSuccess++;
      res.push_back(targets[maxTargetNo]);
      return res;
    } else {
      uniqueThrehsholdReject++;
      return res; // return empty
    }
  }
}


// returns position in array a if found, max if not found
int findStrInArray(char *str, char **a, int max) {
  for (int i=0; i< max; i++) {
    if (strcmp(str, a[i]) == 0) {
      return i;
    }
  }
  return max;
}



vector<string> disambiguateNB(vector<string> &targets, unordered_map<string, INT> &features, int minConceptFreq, double minPosteriorProb,  unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq) {

  uniqueTotalCases++;
  int nbTargets = targets.size();
  vector<string> res;
  //  vector<string> selectedTargets;
  INT *uniFreqTargets = (INT *) malloc(sizeof(INT) * nbTargets);
  //  unordered_map<string, INT> uni; 
  //unordered_map<string, unordered_map<string, INT>> featuresCuis;
  //  unordered_map<string, INT *> featuresCuis;
  //  unordered_map<string, unordered_map<string, INT>> featuresCuis;
  //  unordered_map<string, double> pTargetGivenDoc;
  double *pTargetGivenDoc = (double *) malloc(sizeof(double) * nbTargets);;

  unordered_map<string, INT>**submapsByTarget = (unordered_map<string, INT>**) malloc(sizeof(unordered_map<string, INT>*) * nbTargets);
  INT rowSize = 0;
  //  char **cuis; 
  unordered_map<string,int> cuis;
  INT *featTable; // featTable[]

  int noTargetFound = 1;
  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    string &target = targets[targetNo];
    unordered_map<string, INT>::iterator itUni = uniFreq->find(target);
    if ((itUni != uniFreq->end()) && (itUni->second >= minConceptFreq)) {
      INT uniFreqVal = itUni->second;
      uniFreqTargets[targetNo] = uniFreqVal;
      noTargetFound = 0;
      unordered_map<string, unordered_map<string, INT>*>::iterator itJoint = jointFreq->find(target);
      if (itJoint != jointFreq->end()) {
	unordered_map<string, INT> *m = itJoint->second;
	submapsByTarget[targetNo] = m;
	rowSize += m->size();
      } else {
	submapsByTarget[targetNo] = NULL;
      }
      pTargetGivenDoc[targetNo] = (double) uniFreqVal / (double) totalNbDocs ; // p(C)
    } else {
      if (!ignoreTargetIfNotInPairsData) {
	uniqueUnknownTarget++;
	free(uniFreqTargets);
	free(pTargetGivenDoc);
	return res; // return empty
      }
      uniFreqTargets[targetNo] =  0;
      pTargetGivenDoc[targetNo] = 0; // p(C)
      submapsByTarget[targetNo] = NULL;

    }
  }
  if (noTargetFound) {
    uniqueUnknownTarget++;
    free(uniFreqTargets);
    free(pTargetGivenDoc);
    return res; // return empty
  }

  // allocate for the max possible number of features
  //  cuis = (char **) malloc(sizeof(char *) * rowSize);
  featTable = (INT *) calloc(rowSize * (nbTargets+1), sizeof(INT ));
  int nbCuis = 0;

  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    string &target = targets[targetNo];
    unordered_map<string, INT> *m = submapsByTarget[targetNo];
    if (m != NULL) {
      for (unordered_map<string, INT>::iterator itThis = m->begin();  itThis != m->end(); itThis++) {
	std::vector<string>::iterator itNoTarget = std::find(targets.begin(), targets.end(), itThis->first);
	if (itNoTarget == targets.end()) { // now excluding any target cui from features
	  INT freqCuiThisTargetForCooc = itThis->second;
	  unordered_map<string,int>::iterator it0 = cuis.find(itThis->first);
	  if (it0 == cuis.end()) {
	    int freqOk = minFreqThresholdDone;
	    if (!freqOk) {
	      unordered_map<string, INT>::iterator itCheckFreq = uniFreq->find(itThis->first);
	      freqOk = ((itCheckFreq != uniFreq->end()) && (itCheckFreq->second >= minConceptFreq));
	    }
	    if (freqOk) { // ok, include
	      cuis.insert({itThis->first, nbCuis});
	      unordered_map<string, INT>::iterator itFoundInFeat = features.find(itThis->first);
	      if (itFoundInFeat != features.end()) {
		featTable[rowSize*nbTargets+nbCuis] = 1;
	      }
	      featTable[rowSize*targetNo + nbCuis] = freqCuiThisTargetForCooc;
	      nbCuis++;
	    }
	  } else {  //existing
	    featTable[rowSize*targetNo + it0->second] = freqCuiThisTargetForCooc;
	  }
	}
      }
    }
  }

  for (int cuiNo=0; cuiNo<nbCuis; cuiNo++) {
    //    char *featureCui = cuis[cuiNo];

    //   string featureCuiStr = string(featureCui);
    //    cerr << "DEBUG featureCui="<<featureCui<<endl;
    for (int targetNo=0; targetNo<nbTargets; targetNo++) {
      INT  jointFreqCuiTarget = featTable[rowSize*targetNo + cuiNo];
      //      cerr << "  DEBUG targetNo="<<targetNo<<" ; target = "<<targets[targetNo]<<" ; jointFreqCuiTarget="<<jointFreqCuiTarget<<endl;
      double pFeatGivenTarget = (double) jointFreqCuiTarget / (double) uniFreqTargets[targetNo];
      //      unordered_map<string, INT>::iterator itFoundInFeat = features.find(featureCuiStr);
      //      if (itFoundInFeat != features.end()) {
      if (featTable[rowSize*nbTargets+cuiNo]) { // feature present 
	pTargetGivenDoc[targetNo] *= (double) pFeatGivenTarget;  // * p(Xi|C)
      } else {
	pTargetGivenDoc[targetNo] *= ((double) 1 - (double) pFeatGivenTarget);   // * p(Xi|C)
      }
    }
  }
  // DEBUG  if (totalAmbig>10) {
  //    cerr <<"EXIT"<<endl;
  //    exit(1);
  //  }

  free(featTable);
  //  free(cuis);
  free(uniFreqTargets);
  double marginal = 0;
  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    marginal += pTargetGivenDoc[targetNo];
  }
  if (marginal == 0) {
    uniqueMethodNA++;
    free(pTargetGivenDoc);
    return res; // return empty
  } else {
    int maxTargetNo=-1;
    double maxP=-1;
    //    cerr << "DEBUG FINAL -- marginal="<<marginal<<endl;
    for (int targetNo=0; targetNo<nbTargets; targetNo++) {
      //      string &target = targets[targetNo];
      double p = pTargetGivenDoc[targetNo] / marginal;
      //      cerr <<"  target="<<target<<": "<<p<<endl;
      if (p > maxP) {
	maxTargetNo = targetNo;
	maxP = p;
      }
    }
    free(pTargetGivenDoc);
    if (maxP > minPosteriorProb) {
      uniqueSuccess++;
      res.push_back(targets[maxTargetNo]);
      return res;
    } else {
      uniqueThrehsholdReject++;
      return res; // return empty
    }
  }
  

}




vector<string> disambiguateNB_old(vector<string> &targets, unordered_map<string, INT> &features, int minConceptFreq, double minPosteriorProb,  unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq) {

  uniqueTotalCases++;
  int nbTargets = targets.size();
  vector<string> res;
  //  vector<string> selectedTargets;
  INT *uniFreqTargets = (INT *) malloc(sizeof(INT) * nbTargets);
  //  unordered_map<string, INT> uni; 
  //unordered_map<string, unordered_map<string, INT>> featuresCuis;
  unordered_map<string, INT *> featuresCuis;
  //  unordered_map<string, unordered_map<string, INT>> featuresCuis;
  //  unordered_map<string, double> pTargetGivenDoc;
  double *pTargetGivenDoc = (double *) malloc(sizeof(double) * nbTargets);;

  int noTargetFound = 1;
  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    string &target = targets[targetNo];
    unordered_map<string, INT>::iterator itUni = uniFreq->find(target);
    if ((itUni != uniFreq->end()) && (itUni->second >= minConceptFreq)) {
      INT uniFreqVal = itUni->second;
      uniFreqTargets[targetNo] = uniFreqVal;
      noTargetFound = 0;
      unordered_map<string, unordered_map<string, INT>*>::iterator itJoint = jointFreq->find(target);
      if (itJoint != jointFreq->end()) {
	unordered_map<string, INT> *m = itJoint->second;
	for (unordered_map<string, INT>::iterator itThis = m->begin();  itThis != m->end(); itThis++) {
	  string cui = itThis->first;
	  int freqOk = minFreqThresholdDone;
	  if (!freqOk) {
	    unordered_map<string, INT>::iterator itCheckFreq = uniFreq->find(cui);
	    freqOk = ((itCheckFreq != uniFreq->end()) && (itCheckFreq->second >= minConceptFreq));
	  }
	  if (freqOk) { // ok, include
	    INT freq = itThis->second;
	    unordered_map<string, INT*>::iterator it = featuresCuis.find(cui);
	    INT *a; 
	    if (it != featuresCuis.end()) {
	      a =  it->second;
	      //	      unordered_map<string, INT> &m = it->second;
	      //	      m.insert({target, freq});
	    } else {
	      a =  (INT *) calloc(nbTargets, sizeof(INT)) ;
	      //	      unordered_map<string, INT> m;
	      //	      m.insert({target, freq});
	      //	      featuresCuis.insert({cui, m});
	      featuresCuis.insert({cui, a});
	    }
	    a[targetNo] = freq;
	  }
	}
      }
      pTargetGivenDoc[targetNo] = (double) uniFreqVal / (double) totalNbDocs ; // p(C)
      //      selectedTargets.push_back(target);
    } else {
      if (!ignoreTargetIfNotInPairsData) {
	uniqueUnknownTarget++;
	for (unordered_map<string, INT *>::iterator itFree=featuresCuis.begin(); itFree != featuresCuis.end(); itFree++) { free(itFree->second); }
	free(uniFreqTargets);
	free(pTargetGivenDoc);
	return res; // return empty
      }
      uniFreqTargets[targetNo] =  0;
      pTargetGivenDoc[targetNo] = 0; // p(C)
    }
  }
  if (noTargetFound) {
    uniqueUnknownTarget++;
    for (unordered_map<string, INT *>::iterator itFree=featuresCuis.begin(); itFree != featuresCuis.end(); itFree++) { free(itFree->second); }
    free(uniFreqTargets);
    free(pTargetGivenDoc);
    return res; // return empty
  }

  for (unordered_map<string, INT *>::iterator it = featuresCuis.begin(); it != featuresCuis.end(); it++) {
    string featureCui = it->first;
    INT *jointFreqFeatureByTarget = it->second;
    //    cerr << "DEBUG featureCui="<<featureCui<<endl;
    unordered_map<string, INT>::iterator itFoundInFeat = features.find(featureCui);
    int featPresent = (itFoundInFeat != features.end());
    for (int targetNo=0; targetNo<nbTargets; targetNo++) {
      //      string &target = targets[targetNo];
      //      unordered_map<string, INT>::iterator itJFreq = jointFreqFeatureByTarget.find(target);
      //      INT jointFreqCuiTarget = (itJFreq != jointFreqFeatureByTarget.end()) ? itJFreq->second : 0 ;
      INT  jointFreqCuiTarget = jointFreqFeatureByTarget[targetNo];
      //      cerr << "  DEBUG targetNo="<<targetNo<<" ; target = "<<targets[targetNo]<<" ; jointFreqCuiTarget="<<jointFreqCuiTarget<<endl;
      double pFeatGivenTarget = (double) jointFreqCuiTarget / (double) uniFreqTargets[targetNo];
      //      unordered_map<string, double>::iterator itTargetGivenDoc = pTargetGivenDoc.find(target);
      //      if (itTargetGivenDoc == pTargetGivenDoc.end()) {
      //	cerr << "Bug\n";
      //	exit(52);
      //      }
      //	itTargetGivenDoc->second *= (double) pFeatGivenTarget;  // * p(Xi|C)
      if (featPresent) {
	pTargetGivenDoc[targetNo] *= (double) pFeatGivenTarget;  // * p(Xi|C)
      } else {
	//	itTargetGivenDoc->second *= ((double) 1 - (double) pFeatGivenTarget);   // * p(Xi|C)
	pTargetGivenDoc[targetNo] *= ((double) 1 - (double) pFeatGivenTarget);   // * p(Xi|C)
      }
    }
  }
  // DEBUG  if (totalAmbig>10) {
  //    cerr <<"EXIT"<<endl;
  //    exit(1);
  //  }

  for (unordered_map<string, INT *>::iterator itFree=featuresCuis.begin(); itFree != featuresCuis.end(); itFree++) { free(itFree->second); }
  free(uniFreqTargets);
  double marginal = 0;
  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    marginal += pTargetGivenDoc[targetNo];
  }
  if (marginal == 0) {
    uniqueMethodNA++;
    free(pTargetGivenDoc);
    return res; // return empty
  } else {
    int maxTargetNo=-1;
    double maxP=-1;
    //    cerr << "DEBUG FINAL -- marginal="<<marginal<<endl;
    for (int targetNo=0; targetNo<nbTargets; targetNo++) {
      //      string &target = targets[targetNo];
      double p = pTargetGivenDoc[targetNo] / marginal;
      //      cerr <<"  target="<<target<<": "<<p<<endl;
      if (p > maxP) {
	maxTargetNo = targetNo;
	maxP = p;
      }
    }
    free(pTargetGivenDoc);
    if (maxP > minPosteriorProb) {
      uniqueSuccess++;
      res.push_back(targets[maxTargetNo]);
      return res;
    } else {
      uniqueThrehsholdReject++;
      return res; // return empty
    }
  }
  

}





vector<string> disambiguateAdvanced(vector<string> &targets, unordered_map<string, INT> &features, int minConceptFreq, double minPosteriorProb,  unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq) {

  
  

  uniqueTotalCases++;
  int nbTargets = targets.size();
  //  unordered_map<string, INT> uni;
  INT *uniFreqTargets = (INT *) malloc(sizeof(INT) * nbTargets);
  //unordered_map<string, unordered_map<string, INT>> featuresCuis;
  //  unordered_map<string, INT *> featuresCuis;
  INT *countMatches = (INT *) calloc(nbTargets, sizeof(INT));
  vector<string> res;

  int noTargetFound = 1;
  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
    string &target = targets[targetNo];
    //    cerr << "DEBUG target = "<<target<<endl;
    //    countMatches.insert({target, 0 });
    countMatches[targetNo] = 0;
    unordered_map<string, INT>::iterator itUni = uniFreq->find(target);
    if ((itUni != uniFreq->end()) && (itUni->second >= minConceptFreq)) {
      INT uniFreqVal = itUni->second;
      //      uni.insert({ target, uniFreqVal });
      uniFreqTargets[targetNo] = uniFreqVal;
      noTargetFound = 0;
      /*
      unordered_map<string, unordered_map<string, INT>*>::iterator itJoint = jointFreq->find(target);
      if (itJoint != jointFreq->end()) {
	unordered_map<string, INT> *m = itJoint->second;
	for (unordered_map<string, INT>::iterator itThis = m->begin();  itThis != m->end(); itThis++) {
	  string cui = itThis->first;
	  unordered_map<string, INT>::iterator itCheckFreq = uniFreq->find(cui);
	  if ((itCheckFreq != uniFreq->end()) && (itCheckFreq->second >= minConceptFreq)) {
	    INT freq = itThis->second;
	    unordered_map<string, INT*>::iterator it = featuresCuis.find(cui);
	    INT *a; 
	    if (it != featuresCuis.end()) {
	      //	      unordered_map<string, INT> &m = it->second;
	      //	      m.insert({target, freq});
	      a =  it->second;
	    } else {
	      //	      unordered_map<string, INT> m;
	      //	      m.insert({target, freq});
	      a =  (INT *) calloc(nbTargets, sizeof(INT)) ;
	      featuresCuis.insert({cui, a});
	    }
	    a[targetNo] = freq;
	  }
	}
      }
      */
      //      selectedTargets.push_back(target);
    } else {
      if (!ignoreTargetIfNotInPairsData) {
	uniqueUnknownTarget++;
	//	for (unordered_map<string, INT *>::iterator itFree=featuresCuis.begin(); itFree != featuresCuis.end(); itFree++) { free(itFree->second); }
	free(uniFreqTargets);
	return res; // return empty
      }
      uniFreqTargets[targetNo] =  0;
    }
  }
  if (noTargetFound) {
    uniqueUnknownTarget++;
    //    for (unordered_map<string, INT *>::iterator itFree=featuresCuis.begin(); itFree != featuresCuis.end(); itFree++) { free(itFree->second); }
    free(uniFreqTargets);
    return res; // return empty
  }

  INT totalMatches = 0;
  for (unordered_map<string, INT>::iterator it = features.begin(); it != features.end(); it++) {
    string featCui = it->first;
    INT featFreq = it->second;
    //    unordered_map<string, INT *>::iterator it1 = featuresCuis.find(featCui);
    int freqOk = minFreqThresholdDone;
    if (!freqOk) {
      unordered_map<string, INT>::iterator itCheckFreq = uniFreq->find(featCui);
      freqOk = ((itCheckFreq != uniFreq->end()) && (itCheckFreq->second >= minConceptFreq));
    }
    if (freqOk) { // ok, include
      unordered_map<string, unordered_map<string, INT>*>::iterator itJoint = jointFreq->find(featCui);
      if (itJoint != jointFreq->end()) {
	unordered_map<string, INT> *m = itJoint->second;
	INT *thisFeatCountByTarget = (INT *) calloc(nbTargets, sizeof(INT));
	int thisFeatCountNonZeroTargets = 0;
	for (int targetNo=0; targetNo<nbTargets; targetNo++) {
	  unordered_map<string, INT>::iterator itTarget = m->find(targets[targetNo]);
	  if (itTarget != m->end()) {
	    thisFeatCountByTarget[targetNo] += itTarget->second;;
	    thisFeatCountNonZeroTargets++;
	  }
	}
	if (!advancedDiscriminativeFeatsOnly || (thisFeatCountNonZeroTargets ==1)) {
	  for (int targetNo=0; targetNo<nbTargets; targetNo++) {
	    INT f = thisFeatCountByTarget[targetNo];
	    countMatches[targetNo] += f;
	    totalMatches += f;
	  }
	}
	free(thisFeatCountByTarget);
      }
    }
    
  }

  //  for (unordered_map<string, INT *>::iterator itFree=featuresCuis.begin(); itFree != featuresCuis.end(); itFree++) { free(itFree->second); }
  free(uniFreqTargets);

  if (totalMatches == 0) {
    uniqueMethodNA++;
    free(countMatches);
    return res; //empty
  } else {
    int maxTargetNo = -1;
    double maxP = -1;
    for (int targetNo=0; targetNo<nbTargets; targetNo++) {
      //      unordered_map<string, INT>::iterator it = countMatches.find(target);
      //      INT c = (it != countMatches.end()) ? it->second : 0 ;
      INT c = countMatches[targetNo];
      double p = (double) c / (double) totalMatches;
      if (p > maxP) {
	maxTargetNo = targetNo;
	maxP = p;
      }
    }
    free(countMatches);
    if (maxP > minPosteriorProb) {
      uniqueSuccess++;
      res.push_back(targets[maxTargetNo]);
      return res;
    } else {
      uniqueThrehsholdReject++;
      return res; // return empty
    }


  }
     


  

}



void processOneDoc(string &pmid, ofstream &outFH, unordered_map<string, string> &doc, string &method, int minConceptFreq, double minPosteriorProb, unordered_map<INT, string> *idToCui,  unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq, unordered_map<string, vector<string>> *externalCuisByPMid) {

  unordered_map<string, string> single;
  unordered_map<string, vector<string>> multi;
  unordered_map<string, INT> countSingle;
  unordered_map<string, string> originalMulti;

  unordered_map<string, string>::iterator it;
  for ( it = doc.begin(); it != doc.end(); it++ )  {
    string docKey = it->first;
    string cuisOrIdsStr = it->second;
    vector<string> cuisOrIds = split(cuisOrIdsStr, ',');
    if (idToCui != NULL) {
      for (int i=0; i< cuisOrIds.size(); i++) {
	INT id = strtol(cuisOrIds[i].c_str(), NULL,10);
	unordered_map<INT, string>::iterator itRef = idToCui->find(id);
	if (itRef != idToCui->end()) {
	  cuisOrIds[i] = itRef->second;
	} else {
	  cerr << "Error: cannot find id "<<id<<" in the id to CUI map.\n";
	  exit(6);
	}
      }
    }
    if (ignoreTargetIfNotInPairsData && (cuisOrIds.size()>1)) {  
      // if option enabled, discard any cui which is not in pairs data. 
      // This might cause the ambiguous group to be "downgraded" to a single non-ambiguous target
      // CAUTION: what if no CUI left at all?
      vector<string> passedCuis;
      for (string &cui : cuisOrIds) {
	unordered_map<string, INT>::iterator it = uniFreq->find(cui);
	if ((it != uniFreq->end()) && (it->second >= minConceptFreq)) {
	  passedCuis.push_back(cui);
	}
      }
      cuisOrIds = passedCuis;
    }
    if (cuisOrIds.size()>0) {
      if (cuisOrIds.size()>1) {
	multi.insert({ cuisOrIdsStr, cuisOrIds });
	std::sort(cuisOrIds.begin(), cuisOrIds.end());
	originalMulti.insert({  cuisOrIdsStr, join(cuisOrIds,",") });
      } else {
	single.insert({ cuisOrIdsStr, cuisOrIds[0] });
	unordered_map<string, INT>::iterator sc = countSingle.find(cuisOrIds[0]);
	if (sc != countSingle.end()) {
	  (sc->second)++;
	} else {
	  countSingle.insert({cuisOrIds[0], 1});
	}
      }
    } else { // if no CUI left at all due to ignoreTargetIfNotInPairsData, ignore entirely
      totalDiscardedDueToNotInPairsData++;
    }
  }

  if (externalCuisByPMid != NULL) { // adding external CUIs based on PMID (typically from Mesh descriptors) to features
    if (pmid.substr(0,6) != "NOPMID") {
      string realPmid = split(pmid, '.')[0];
      unordered_map<string, vector<string>>::iterator itExtern =  externalCuisByPMid->find(realPmid);
      if (itExtern != externalCuisByPMid->end()) {
	//	cerr << "DEBUG: external cuis found for pmid "<<realPmid<<endl;
	vector<string> &externCuis = itExtern->second;
	for (string c: externCuis) {
	  unordered_map<string, INT>::iterator sc = countSingle.find(c);
	  if (sc != countSingle.end()) {
	    (sc->second)++;
	  } else {
	    countSingle.insert({c, 1});
	  }
	}
	//      } else {
	//	cerr << "DEBUG: external cuis NOT found for pmid "<<realPmid<<endl;
      }
    }
  }


  unordered_map<string, vector<string>> disamb;
  unordered_map<string, vector<string>>::iterator itamb;
  for (itamb = multi.begin(); itamb != multi.end(); itamb++ )  {
    string cuisOrIdsStr = itamb->first;
    vector<string> &cuis = itamb->second;
    vector<string> res;
    if (method == "basic") {
      res = disambiguateBasic(cuis, countSingle, minConceptFreq, minPosteriorProb, uniFreq, jointFreq);
    } else {
      // for both advanced and NB, exclude target CUIs from features
      for (string &target : cuis) {
	unordered_map<string, INT>::iterator itRm = countSingle.find(target);
	if (itRm != countSingle.end()) {
	  countSingle.erase(itRm);
	}
      }
      if (method == "advanced") {
	res = disambiguateAdvanced(cuis, countSingle, minConceptFreq, minPosteriorProb, uniFreq, jointFreq);
      } else {
	if (method == "NB") {
	  res = disambiguateNB(cuis, countSingle, minConceptFreq, minPosteriorProb, uniFreq, jointFreq);
	} else {
	  cerr << "Error: invalid method id '"<<method<<"' \n";
	  exit(10);
	}

      }
    }
    disamb.insert({cuisOrIdsStr, res});
  }

  for ( it = doc.begin(); it != doc.end(); it++ )  {
    string docKey = it->first;
    vector<string> keyParts = split(docKey, ',');
    string cuisOrIdsStr = it->second;
    string newIdsStr;
    totalCases++;
    itamb = multi.find(cuisOrIdsStr);
    if (itamb != multi.end()) { // ambiguous case
      totalAmbig++;
      unordered_map<string, vector<string>>::iterator itnew = disamb.find(cuisOrIdsStr);
      if ((itnew != disamb.end()) && (itnew->second.size()>0)) { // ambiguous fixed
	ambigFixed++;
	newIdsStr = join(itnew->second, ",");
      } else {
	unordered_map<string,string>::iterator itO = originalMulti.find(cuisOrIdsStr);
	if (itO != originalMulti.end()) {
	  newIdsStr = itO->second;
	} else {
	  cerr << "Bug: can't find key supposed to be in the map\n";
	  exit(20);
	}
      }
    } else {
      unordered_map<string,string>::iterator itsingle = single.find(cuisOrIdsStr);
      if (itsingle != single.end()) {
	newIdsStr = itsingle->second;
      } // else {
	// this case can happen now when all the cuis have been discarded due to ignoreTargetIfNotInPairsData
        // nothing is done so newIdsStr stays empty and we don't print anything
	//	  cerr << "Bug: can't find key supposed to be in the map\n";
	//	  exit(20);
      //      }
    }

    if (newIdsStr.length()>0) { // possibly not initialized due to ignoreTargetIfNotInPairsData
      outFH << pmid <<"\t"<< keyParts[0]<<"\t"<< keyParts[1]<<"\t"<< keyParts[2]<<"\t"<< newIdsStr <<"\t"<< keyParts[3] <<"\t"<< keyParts[4]<<  endl;
    }
  }
}

void processFile(string &dataFile, string &method, int minConceptFreq, double minPosteriorProb, unordered_map<INT, string> *idToCui,  unordered_map<string, INT>* uniFreq, unordered_map<string, unordered_map<string, INT>*> *jointFreq, string outputDir, unordered_map<string, vector<string>> *externalCuisByPMid) {

  const string suffix = ".out.cuis";
  if (dataFile.substr(dataFile.length()-suffix.length(), suffix.length()) !=  suffix) {
    cerr << "Error: data filename '"<<dataFile<<"' does not end with '"<<suffix<<"' "<<endl;
    exit(3);
  }
  string baseFile = string(basename(strdup(dataFile.c_str())));
  string outputFile = outputDir+"/"+baseFile;
  
  ofstream outFH;
  outFH.open(outputFile);
  if (!outFH) {
    cerr << "Error opening "<< outputFile << endl;
    exit(1);
  }

  ifstream inFH(dataFile);
  if (!inFH) {
    cerr << "Error opening "<< dataFile << endl;
    exit(1);
  }

  unordered_map<string,string> dataOneDoc;
  string lastPMID;
  string str; 
  while (getline(inFH, str)) {
    vector<string> cols = split(str,'\t');
    if (cols.size() != 7) {
      cerr << "Error: expecting 7 columns in '"<<dataFile<<"'\n";
      exit(5);
    }
    string pmid = cols[0];
    string docType = cols[1];
    string docId = cols[2];
    string sentNo = cols[3];
    string cuisOrIds = cols[4];
    string pos = cols[5];
    string length = cols[6];
    string docKey = docType+","+docId+","+sentNo+","+pos+","+length;

    if ( (lastPMID.length()>0) && (lastPMID != pmid)) {
      processOneDoc(lastPMID, outFH, dataOneDoc, method, minConceptFreq, minPosteriorProb, idToCui, uniFreq, jointFreq, externalCuisByPMid);
      dataOneDoc.clear();
    }
    dataOneDoc.insert({ docKey, cuisOrIds });
    lastPMID = pmid;
  }
  if (lastPMID.length()>0) {
    processOneDoc(lastPMID, outFH, dataOneDoc, method, minConceptFreq, minPosteriorProb, idToCui, uniFreq, jointFreq, externalCuisByPMid);
  }
  inFH.close();
  outFH.close();

  string statsOutputFile = outputDir+".stats";
  outFH.open(statsOutputFile);
  if (!outFH) {
    cerr << "Error opening "<< statsOutputFile << endl;
    exit(1);
  }

  outFH << "\nTotal: "<<totalCases<<endl;
  outFH << "Discarded (if option -d): "<<totalDiscardedDueToNotInPairsData<<"  ("<<strProp(totalDiscardedDueToNotInPairsData,totalCases)<<" %)" <<endl;
  outFH << "Ambiguous: "<<totalAmbig<<" ("<<strProp(totalAmbig,totalCases)<<" %)"<<endl;
  outFH << "Ambiguous fixed: "<<ambigFixed<<"  ("<<strProp(ambigFixed,totalAmbig)<<" %)"<<endl;
  outFH << "\nTotal unique ambiguity cases: "<<uniqueTotalCases<<"\n";
  outFH <<  "  Success: "<<uniqueSuccess<<" ("<<strProp(uniqueSuccess,uniqueTotalCases)<<" %)\n";
  outFH <<  "  Failed - Unknown target: "<<uniqueUnknownTarget<<" ("<<strProp(uniqueUnknownTarget,uniqueTotalCases)<<" %)\n";
  outFH <<  "  Failed - Method Not Applicable: "<<uniqueMethodNA<<" ("<<strProp(uniqueMethodNA,uniqueTotalCases)<<" %)\n";
  outFH <<  "  Failed - Rejected due to threshold: "<<uniqueThrehsholdReject<<" ("<<strProp(uniqueThrehsholdReject,uniqueTotalCases)<<" %)\n\n";

  

  outFH.close();
}




int main(int argc, char **argv) {

  string cuiRefFile;
  //  int inputAsFile=0;
  int multiParameterValues=0;

  unordered_map<INT, string> *idToCui = NULL;
  unordered_map<string, INT>* uniFreq  = new unordered_map<string, INT>();
  unordered_map<string, unordered_map<string, INT>*> *jointFreq  = new unordered_map<string, unordered_map<string, INT>*>();

  

  int option;
  // put ':' at the starting of the string so compiler can distinguish between '?' and ':'
  while((option = getopt(argc, argv, ":hr:f:b:a:dAMe:")) != -1){ //get option from the getopt() method
    switch(option){
      //For option i, r, l, print that these are options
    case 'h':
      usage(cout);
      exit(0);
    case 'r':
      cuiRefFile = optarg;
      break;
    case 'f':
      //      minConceptFreq0 = atoi(optarg);
      minConceptFreq0 = optarg;
      break;
    case 'b':
      //      minPosteriorProb0 = atof(optarg);
      minPosteriorProb0 = optarg;
      break;
    case 'a':
      method0 = optarg;
      break;
    case 'd':
      ignoreTargetIfNotInPairsData = 1;
      break;
    case 'A':
      advancedDiscriminativeFeatsOnly = 0;
      break;
    case 'M':
      multiParameterValues=1;
      break;
    case 'e':
      externalCuisByPmidOpts = split(optarg, ':');
      break;
    case ':':
      printf("option needs a value\n");
      break;
    case '?': //used for some unknown options
      printf("unknown option: %c\n", optopt);
      break;
    }
  }

  if (argc != optind+3) {
    cerr << "Error, 3 arguments required."<<endl;
    usage(cerr);
    exit(1);
  }
  //  string minedDir = argv[optind+0];
  totalNbDocs = strtol(argv[optind+0], NULL,10);
  string pairsStatsFile = argv[optind+1];
  string outputDir = argv[optind+2];

  vector<string> methods = split(method0,':');
  vector<string> minConceptFreqs = split(minConceptFreq0,':');
  vector<string> minPosteriorProbs = split(minPosteriorProb0,':');
  int minMinConceptFreq = 999999;
  if ( minConceptFreqs.size()==1) {
    minFreqThresholdDone = 1;
    minMinConceptFreq = atoi(minConceptFreqs[0].c_str());
  } else {
    for (string val : minConceptFreqs) {
      if (atoi(val.c_str())<minMinConceptFreq) {
	minMinConceptFreq = atoi(val.c_str());
      }
    }
  }

  if (!multiParameterValues && ((methods.size()>1) || (minConceptFreqs.size()>1) || (minPosteriorProbs.size()>1) ) ) {
    cerr << "Error: must use -m with multiple parameters values."<<endl;
    exit(1);
  }

  createDirIfNeeded(outputDir.c_str());

  vector<string> dataFiles;
  string str; 
  while (getline(cin, str)) {
    dataFiles.push_back(str);
  }
  if (dataFiles.size()==0) {
    cerr << "Error: zero input files read from STDIN" << endl;
    exit(3);
  }

  if (cuiRefFile.length()>0) {
    cerr << "Reading reference file '" << cuiRefFile<<"'" <<endl;
    idToCui = readCuiRefFile(cuiRefFile);
  }

  unordered_map<string, vector<string>> *externalCuisByPMid = NULL;
  if (externalCuisByPmidOpts.size()>0) {
    if (externalCuisByPmidOpts.size() != 4) {
      cerr << "Error: format error in option -e"<<endl;
      exit(8);
    }
    string &filename = externalCuisByPmidOpts[0];
    int colPMIDNo = atoi(externalCuisByPmidOpts[1].c_str()); 
    int colCuisNo = atoi(externalCuisByPmidOpts[2].c_str());
    char separator = externalCuisByPmidOpts[3].at(0);

    cerr << "Reading external CUIs  file '" << filename <<"'" <<endl;
    externalCuisByPMid = readExternalResource(filename, colPMIDNo, colCuisNo, separator);
 }


  
  if (multiParameterValues || (method0 == "NB") || (method0 == "advanced") ) {
    cerr << "Reading pairs stats file '" << pairsStatsFile <<"'" <<endl;
    readPairsData(pairsStatsFile, uniFreq, jointFreq, minMinConceptFreq);
  }


  for (string method : methods) {
    for (string minConceptFreqStr : minConceptFreqs) {
      int minConceptFreq = atoi(minConceptFreqStr.c_str());
      for (string minPosteriorProbStr : minPosteriorProbs) {
	resetStatsCase();
	double minPosteriorProb = atof(minPosteriorProbStr.c_str());
	cerr << "Processing method="<<method<<"; minConceptFreq="<<minConceptFreq<<"; minPosteriorProb="<<minPosteriorProb<<"...\n";
	string thisOutputDir = outputDir;
	if (multiParameterValues)  {
	  thisOutputDir = outputDir+"/"+method+"_"+ minConceptFreqStr+"_"+minPosteriorProbStr;
	  createDirIfNeeded(thisOutputDir.c_str());
	}


	for (int fileNo=0; fileNo<dataFiles.size(); fileNo++) {
	  string dataFile = dataFiles[fileNo];
	  cerr << "\rProcessing data file '"<<dataFile<<"' [ "<<fileNo<<" / "<<dataFiles.size()<<" ] ... ";
	  processFile(dataFile, method, minConceptFreq, minPosteriorProb, idToCui, uniFreq, jointFreq, thisOutputDir, externalCuisByPMid);
	}
	cerr <<endl;
      }
    }
  }

  
}

