document.addEventListener("DOMContentLoaded", function() {
    console.log("Document loaded");
    console.log(window.location.pathname);
    console.log('blaat');
    getTeamList();
    // // Interval function to do a refresh
    // setInterval( function(){
    //     console.log("refresh triggered");
    //     doRefresh();
    // }, 1000 * 60 * 5);
    // Haal de teams op
    function getTeamList(){
        console.log('getTeamList');
        // fetch('/api/getTeamList')
        // .then( res => {
        //     return res.json();
        // })
        // .then( data => {
        //     console.log(data);
        var teamTable = document.querySelector('#teamlist_table');
        if (teamTable){
            const table = document.createElement(`table`);
            table.style.cssText += "border-collapse: collapse;"
            const aRow = document.createElement(`tr`);
            const aCell = document.createElement(`td`);
            const aHead = document.createElement(`th`);
        
            // Headers
            const row = aRow.cloneNode();
            const headerName  = aHead.cloneNode();
            headerName.textContent = 'Naam';
            row.append(headerName);
            const headerDocenten = aHead.cloneNode();
            headerDocenten.textContent = 'Docenten';
            row.append(headerDocenten);
            const headerLLN = aHead.cloneNode();
            headerLLN.textContent = 'Leerlingen';
            row.append(headerLLN);
            table.append(row);

            fetch("/api/getTeamList")
            .then( res => {
              return res.json();
            })
            .then( data => {
                for (const[secureName, team] of Object.entries(data)){
                // data.forEach(obj =>{
                    const row = aRow.cloneNode();
                    row.style.cssText += `border-bottom: 2pt solid ${team.color};`;
                    //Name
                    const cellSecureName = aCell.cloneNode();
                    cellSecureName.textContent = secureName;
                    row.append(cellSecureName);
                    //Docenten
                    const cellDocenten = aCell.cloneNode();
                    cellDocenten.textContent = team.docenten;
                    row.append(cellDocenten);
                    //Leerlingen
                    const cellLLN = aCell.cloneNode();
                    cellLLN.textContent = team.lln;
                    row.append(cellLLN);
                    table.append(row);
                };
                teamTable.textContent = '';
                teamTable.append(table);
            })
            .catch( err => {
                console.warn('Oeps getGroepen', err);
            });
        }
    }
});