document.addEventListener("DOMContentLoaded", function() {
    console.log("Document loaded");

    // Init
    // var currentRow = 1;
    var pageSize = 25;

    // Register EventHandlers for the navBar
    document.querySelector("#navFirst").addEventListener("click", (e) =>{
        getTeamList(0,pageSize)
    });
    document.querySelector("#navPrev").addEventListener("click", (e) =>{
        //var rowCount = document.querySelector('#rowCount').value;
        var rowStart = document.querySelector('#rowStart').value;
        var newStart = rowStart - pageSize;
        if (newStart < 0){
            console.log('reset naar 0');
            newStart = 0;
        }
        getTeamList(newStart,pageSize);
    });
    document.querySelector("#navNext").addEventListener("click", (e) =>{
        var rowCount = document.querySelector('#rowCount').value;
        var rowStart = document.querySelector('#rowStart').value;
        var newStart = Number(rowStart) + Number(pageSize);
        if (newStart >= rowCount){
            console.log('reset naar rowCount - page');
            newStart = Number(rowCount) - Number(pageSize);
        }
        getTeamList(newStart,pageSize);
    });
    document.querySelector("#navLast").addEventListener("click", (e) =>{
        var rowCount = document.querySelector('#rowCount').value;
        getTeamList(Number(rowCount)-Number(pageSize),pageSize)
    });
    document.querySelector("#navSearch").addEventListener("keyup", (e) =>{
        console.log('search keyup');
        console.log(e)
        var searchFor = document.querySelector("#navSearch").value;
        if(searchFor.length > 2){
            getTeamList(0,pageSize,searchFor);
        }else{
            getTeamList(0,pageSize);
        }
    });

    getTeamList(0,pageSize);


    
    function getTeamList(from,page,search){
        console.log('getTeamList');
        var teamTable = document.querySelector('#teamlist_table');
        if (teamTable){
            const table = document.createElement(`table`);
            table.style.cssText += "border-collapse: collapse;"
            const aRow = document.createElement(`tr`);
            const aCell = document.createElement(`td`);
            const aHead = document.createElement(`th`);
            const aLink = document.createElement(`a`);
        
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

            var request = `/api/getTeamList/${from}/${page}/${search}`;
            console.log(request);
            fetch(request)
            .then( res => {
              return res.json();
            })
            .then( data => {
                document.querySelector('#rowCount').value = data.rowCount.count;
                document.querySelector('#rowStart').value = data.rowCount.start;
                //console.log(document.querySelector('#rowStart').value);
                console.log(data.teams);
                for (const[naam, team] of Object.entries(data.teams).sort()){
                    const row = aRow.cloneNode();
                    row.style.cssText += `border-bottom: 2pt solid ${team.color};`;
                    //Name
                    const teamLink = document.createElement('a');
                    teamLink.innerHTML = naam;
                    teamLink.href = `/teamDetail/${naam}`;
                    console.log(teamLink);
                    const cellNaam = document.createElement('td');
                    cellNaam.append(teamLink);
                    //console.log(naam);
                    row.append(cellNaam);
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
                console.warn('Oeps getTeams', err);
            });
        }
    }
});
