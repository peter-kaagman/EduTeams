document.addEventListener("DOMContentLoaded", function() {
    console.log("Document loaded");

    // Init
    // var currentRow = 1;
    var pageSize = 25;

    // Register EventHandlers for the navBar
    document.querySelector("#navFirst").addEventListener("click", (e) =>{
        getStafList(0,pageSize)
    });
    document.querySelector("#navPrev").addEventListener("click", (e) =>{
        //var rowCount = document.querySelector('#rowCount').value;
        var rowStart = document.querySelector('#rowStart').value;
        var newStart = rowStart - pageSize;
        if (newStart < 0){
            console.log('reset naar 0');
            newStart = 0;
        }
        getStafList(newStart,pageSize);
    });
    document.querySelector("#navNext").addEventListener("click", (e) =>{
        var rowCount = document.querySelector('#rowCount').value;
        var rowStart = document.querySelector('#rowStart').value;
        var newStart = Number(rowStart) + Number(pageSize);
        if (newStart >= rowCount){
            console.log('reset naar rowCount - page');
            newStart = Number(rowCount) - Number(pageSize);
        }
        getStafList(newStart,pageSize);
    });
    document.querySelector("#navLast").addEventListener("click", (e) =>{
        var rowCount = document.querySelector('#rowCount').value;
        getStafList(Number(rowCount)-Number(pageSize),pageSize)
    });
    document.querySelector("#navSearch").addEventListener("keyup", (e) =>{
        console.log('search keyup');
        console.log(e)
        var searchFor = document.querySelector("#navSearch").value;
        if(searchFor.length > 2){
            getStafList(0,pageSize,searchFor);
        }else{
            getStafList(0,pageSize);
        }
    });

    getStafList(0,pageSize);


    
    function getStafList(from,page,search){
        console.log('getStafList');
        var stafTable = document.querySelector('#staflist_table');
        if (stafTable){
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
            
            const headerLocatie = aHead.cloneNode();
            headerLocatie.textContent = 'Locatie';
            row.append(headerLocatie);
            
            const headerTeams = aHead.cloneNode();
            headerTeams.textContent = 'Teams';
            row.append(headerTeams);

            table.append(row);

            var request = `/api/getStafList/${from}/${page}/${search}`;
            console.log(request);
            fetch(request)
            .then( res => {
              return res.json();
            })
            .then( data => {
                document.querySelector('#rowCount').value = data.rowCount.count;
                document.querySelector('#rowStart').value = data.rowCount.start;
                //console.log(document.querySelector('#rowStart').value);
                console.log(data.users);
                for (const[naam, user] of Object.entries(data.users).sort()){
                    const row = aRow.cloneNode();
                    row.style.cssText += `border-bottom: 2pt solid ${user.color};`;
            
                    //Name
                    const userLink = document.createElement('a');
                    userLink.innerHTML = naam;
                    userLink.href = `/userDetail/${user.upn}`;
                    console.log(userLink);
                    const cellNaam = document.createElement('td');
                    cellNaam.append(userLink);
                    //console.log(naam);
                    row.append(cellNaam);
            
                    //Locatie
                    const cellLocatie = aCell.cloneNode();
                    cellLocatie.textContent = user.locatie;
                    row.append(cellLocatie);
            
                    //Teams
                    const cellTeams = aCell.cloneNode();
                    cellTeams.textContent = user.teamcount;
                    row.append(cellTeams);

                    table.append(row);
                };
                stafTable.textContent = '';
                stafTable.append(table);
            })
            .catch( err => {
                console.warn('Oeps getTeams', err);
            });
        }
    }
});
