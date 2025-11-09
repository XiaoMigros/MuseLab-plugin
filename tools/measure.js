//===================================================//
//Measure information for MuseLab
//forked from XiaoMigros/Beam_Over_Rests
//v 1.0
//changelog:
//===================================================//

//this function maps every measure in the score, their start ticks, their length, and their time signature.
function mapMeasures() {
	var c = curScore.newCursor();
	c.rewind(Cursor.SCORE_START);
	mno		= 0
	mstart	= []
	mlen	= []
	maTsN	= []
	maTsD	= []
	mnTsN	= []
	mnTsD	= []
	while ((c.measure) && (c.tick < curScore.lastMeasure.firstSegment.tick+1)) {
		var m = c.measure; 
		var aTsN = m.timesigActual.numerator;
		var aTsD = m.timesigActual.denominator;
		var nTsN = m.timesigNominal.numerator;
		var nTsD = m.timesigNominal.denominator;
		var mTicks = division * 4.0 * aTsN / aTsD;
		mstart.push(m.firstSegment.tick)
		mlen.push(mTicks);
		maTsN.push(aTsN);
		maTsD.push(aTsD);
		mnTsN.push(nTsN);
		mnTsD.push(nTsD);
		console.log(mlen[mno] + " tick long measure at tick " + mstart[mno] + ". TS: " + maTsN[mno] + "/" + maTsD[mno] +
		((aTsN == nTsN && aTsD == nTsD) ? ("") : (" (actual: " + maTsN[mno] + "/" + maTsD[mno] + ")")) + ",  measure no. " + (mno+1));
		c.nextMeasure();
		mno += 1;
	} //while
	console.log("built measure map")
} //function

function realEndOfMeasure(measure) {
	return division * 4.0 * measure.timesigActual.numerator / measure.timesigActual.denominator;
}
function fakeEndOfMeasure(measure) {
	return division * 4.0 * measure.timesigNominal.numerator / measure.timesigNominal.denominator;
}