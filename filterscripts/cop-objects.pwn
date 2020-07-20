#define 	FILTERSCRIPT
#include 	<a_samp>
#include    "../includes/sqlitei.inc"
#include    "../includes/mSelection.inc"
#include    "../includes/streamer.inc"
#include    "../includes/zcmd.inc"


#define IsACop(%1) CallRemoteFunction("IsACop", "i", %1)
#define IsAdmin(%1) CallRemoteFunction("IsAdmin", "i", %1)
#define SendRadioMessage(%1) CallRemoteFunction("SendRadioMessage", "ixs", 1, 0x2641FEAA, %1)

#if !defined GetConsoleVarAsString
	#error "You need 0.3.7 R2-1 to compile this script."
#endif


#define     MAX_COP_OBJECTS     (300)
#define     COPOBJECTS_DIALOG   (6450)
#define     SPEEDCAM_RANGE      (30.0)

enum    _:e_object_types
{
	OBJECT_TYPE_ROADBLOCK,
	OBJECT_TYPE_SIGN,
	OBJECT_TYPE_POLICELINE,
	OBJECT_TYPE_SPIKE,
	OBJECT_TYPE_SPEEDCAM
}

enum	e_object_data
{
	Owner[MAX_PLAYER_NAME],
	Type,
	ObjData,
	ObjModel,
	Float: ObjX,
	Float: ObjY,
	Float: ObjZ,
	Float: ObjRX,
	Float: ObjRY,
	Float: ObjRZ,
	ObjInterior,
	ObjVirtualWorld,
	ObjID,
	Text3D: ObjLabel,
	ObjArea,
	bool: ObjCreated
}

new
	CopObjectData[MAX_COP_OBJECTS][e_object_data],
	EditingCopObjectID[MAX_PLAYERS] = {-1, ...},
	RoadblockList = mS_INVALID_LISTID,
	SignList = mS_INVALID_LISTID;

new
    Float: zOffsets[5] = {1.35, 3.25, 0.35, 0.4, 5.35},
    Float: streamDistances[5] = {10.0, 10.0, 5.0, 3.0, SPEEDCAM_RANGE};

new
	DB: ObjectDB,
	DBStatement: LoadObjects,
	DBStatement: AddObject,
	DBStatement: UpdateObject,
	DBStatement: RemoveObject;


stock GetFreeObjectID()
{
	new id = -1;
	for(new i; i < MAX_COP_OBJECTS; i++)
	{
	    if(!CopObjectData[i][ObjCreated])
	    {
	        id = i;
	        break;
	    }
	}

	return id;
}

stock GetPlayerSpeed(playerid)
{
    new Float:vx, Float:vy, Float:vz, Float:vel;
	vel = GetVehicleVelocity(GetPlayerVehicleID(playerid), vx, vy, vz);
	vel = (floatsqroot(((vx*vx)+(vy*vy))+(vz*vz))* 181.5);
	return floatround(vel);
}

stock InsertObjectToDB(id)
{
    stmt_bind_value(AddObject, 0, DB::TYPE_INTEGER, id);
	stmt_bind_value(AddObject, 1, DB::TYPE_STRING, CopObjectData[id][Owner]);
	stmt_bind_value(AddObject, 2, DB::TYPE_INTEGER, CopObjectData[id][Type]);
	stmt_bind_value(AddObject, 3, DB::TYPE_INTEGER, CopObjectData[id][ObjData]);
    stmt_bind_value(AddObject, 4, DB::TYPE_INTEGER, CopObjectData[id][ObjModel]);
	stmt_bind_value(AddObject, 5, DB::TYPE_FLOAT, CopObjectData[id][ObjX]);
	stmt_bind_value(AddObject, 6, DB::TYPE_FLOAT, CopObjectData[id][ObjY]);
	stmt_bind_value(AddObject, 7, DB::TYPE_FLOAT, CopObjectData[id][ObjZ]);
	stmt_bind_value(AddObject, 8, DB::TYPE_FLOAT, CopObjectData[id][ObjRX]);
	stmt_bind_value(AddObject, 9, DB::TYPE_FLOAT, CopObjectData[id][ObjRY]);
	stmt_bind_value(AddObject, 10, DB::TYPE_FLOAT, CopObjectData[id][ObjRZ]);
	stmt_bind_value(AddObject, 11, DB::TYPE_INTEGER, CopObjectData[id][ObjInterior]);
	stmt_bind_value(AddObject, 12, DB::TYPE_INTEGER, CopObjectData[id][ObjVirtualWorld]);
	stmt_execute(AddObject);
	return 1;
}

stock SaveObjectToDB(id)
{
    stmt_bind_value(UpdateObject, 0, DB::TYPE_FLOAT, CopObjectData[id][ObjX]);
	stmt_bind_value(UpdateObject, 1, DB::TYPE_FLOAT, CopObjectData[id][ObjY]);
	stmt_bind_value(UpdateObject, 2, DB::TYPE_FLOAT, CopObjectData[id][ObjZ]);
	stmt_bind_value(UpdateObject, 3, DB::TYPE_FLOAT, CopObjectData[id][ObjRX]);
	stmt_bind_value(UpdateObject, 4, DB::TYPE_FLOAT, CopObjectData[id][ObjRY]);
	stmt_bind_value(UpdateObject, 5, DB::TYPE_FLOAT, CopObjectData[id][ObjRZ]);
	stmt_bind_value(UpdateObject, 6, DB::TYPE_INTEGER, id);
	stmt_execute(UpdateObject);
	return 1;
}

encode_tires(tire1, tire2, tire3, tire4) return tire1 | (tire2 << 1) | (tire3 << 2) | (tire4 << 3);

public OnFilterScriptInit()
{
	RoadblockList = LoadModelSelectionMenu("roadblocks.txt");
	SignList = LoadModelSelectionMenu("signs.txt");
	
	ObjectDB = db_open("cop_objects.db");
    db_query(ObjectDB, "CREATE TABLE IF NOT EXISTS objects (id INTEGER, owner TEXT, type INTEGER, data INTEGER, model INTEGER, posx FLOAT, posy FLOAT, posz FLOAT, rotx FLOAT, roty FLOAT, rotz FLOAT, interior INTEGER, virtualworld INTEGER)");

    LoadObjects = db_prepare(ObjectDB, "SELECT * FROM objects");
    AddObject = db_prepare(ObjectDB, "INSERT INTO objects (id, owner, type, data, model, posx, posy, posz, rotx, roty, rotz, interior, virtualworld) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    UpdateObject = db_prepare(ObjectDB, "UPDATE objects SET posx=?, posy=?, posz=?, rotx=?, roty=?, rotz=? WHERE id=?");
	RemoveObject = db_prepare(ObjectDB, "DELETE FROM objects WHERE id=?");
	
	new id, type, data, model, owner[MAX_PLAYER_NAME], Float: pos[3], Float: rot[3], interior, vworld;
	stmt_bind_result_field(LoadObjects, 0, DB::TYPE_INTEGER, id);
	stmt_bind_result_field(LoadObjects, 1, DB::TYPE_STRING, owner, MAX_PLAYER_NAME);
	stmt_bind_result_field(LoadObjects, 2, DB::TYPE_INTEGER, type);
	stmt_bind_result_field(LoadObjects, 3, DB::TYPE_INTEGER, data);
	stmt_bind_result_field(LoadObjects, 4, DB::TYPE_INTEGER, model);
	stmt_bind_result_field(LoadObjects, 5, DB::TYPE_FLOAT, pos[0]);
	stmt_bind_result_field(LoadObjects, 6, DB::TYPE_FLOAT, pos[1]);
	stmt_bind_result_field(LoadObjects, 7, DB::TYPE_FLOAT, pos[2]);
	stmt_bind_result_field(LoadObjects, 8, DB::TYPE_FLOAT, rot[0]);
	stmt_bind_result_field(LoadObjects, 9, DB::TYPE_FLOAT, rot[1]);
	stmt_bind_result_field(LoadObjects, 10, DB::TYPE_FLOAT, rot[2]);
	stmt_bind_result_field(LoadObjects, 11, DB::TYPE_INTEGER, interior);
	stmt_bind_result_field(LoadObjects, 12, DB::TYPE_INTEGER, vworld);

	if(stmt_execute(LoadObjects))
	{
	    new label[96];
	    while(stmt_fetch_row(LoadObjects))
	    {
            CopObjectData[id][ObjCreated] = true;
            CopObjectData[id][Owner] = owner;
		    CopObjectData[id][Type] = type;
		    CopObjectData[id][ObjData] = data;
		    CopObjectData[id][ObjModel] = model;
		    CopObjectData[id][ObjInterior] = interior;
		    CopObjectData[id][ObjVirtualWorld] = vworld;
			CopObjectData[id][ObjX] = pos[0];
			CopObjectData[id][ObjY] = pos[1];
			CopObjectData[id][ObjZ] = pos[2];
			CopObjectData[id][ObjRX] = rot[0];
			CopObjectData[id][ObjRY] = rot[1];
			CopObjectData[id][ObjRZ] = rot[2];
			CopObjectData[id][ObjID] = CreateDynamicObject(model, pos[0], pos[1], pos[2], rot[0], rot[1], rot[2], vworld, interior);
			CopObjectData[id][ObjArea] = -1;
			
			switch(type)
			{
			    case OBJECT_TYPE_ROADBLOCK: format(label, sizeof(label), "Roadblock (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
			    case OBJECT_TYPE_SIGN: format(label, sizeof(label), "Sign (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
			    case OBJECT_TYPE_POLICELINE: format(label, sizeof(label), "Police Line (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
			    case OBJECT_TYPE_SPIKE:
				{
					format(label, sizeof(label), "Spike Strip (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
					CopObjectData[id][ObjArea] = CreateDynamicSphere(pos[0], pos[1], pos[2], 2.5, vworld, interior);
				}
				
				case OBJECT_TYPE_SPEEDCAM:
				{
					format(label, sizeof(label), "Speed Camera (ID: %d)\n{FFFFFF}Speed Limit: {E74C3C}%d\n{FFFFFF}Placed by %s", id, data, CopObjectData[id][Owner]);
					CopObjectData[id][ObjArea] = CreateDynamicSphere(pos[0], pos[1], pos[2], SPEEDCAM_RANGE, vworld, interior);
				}
			}
			
			CopObjectData[id][ObjLabel] = CreateDynamic3DTextLabel(label, 0x3498DBFF, pos[0], pos[1], pos[2] + zOffsets[type], streamDistances[type], _, _, _, vworld, interior);
		}
	}
	
	return 1;
}

public OnFilterScriptExit()
{
	db_close(ObjectDB);
	return 1;
}

public OnPlayerConnect(playerid)
{
	EditingCopObjectID[playerid] = -1;
	return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	if(dialogid == COPOBJECTS_DIALOG)
	{
		if(!response) return 1;
		if(listitem == 0) ShowModelSelectionMenu(playerid, RoadblockList, "Roadblocks", 0x393939BB, 0x3498DBBB);
		if(listitem == 1) ShowModelSelectionMenu(playerid, SignList, "Signs", 0x393939BB, 0x3498DBBB);

		if(listitem == 2)
		{
		    new id = GetFreeObjectID();
		    if(id == -1) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Cop object limit reached.");
		    CopObjectData[id][ObjCreated] = true;
		    GetPlayerName(playerid, CopObjectData[id][Owner], MAX_PLAYER_NAME);
		    CopObjectData[id][Type] = OBJECT_TYPE_POLICELINE;
		    CopObjectData[id][ObjModel] = 19834;
		    CopObjectData[id][ObjInterior] = GetPlayerInterior(playerid);
		    CopObjectData[id][ObjVirtualWorld] = GetPlayerVirtualWorld(playerid);
		    
		    new Float: x, Float: y, Float: z, Float: a;
		    GetPlayerPos(playerid, x, y, z);
		    GetPlayerFacingAngle(playerid, a);
		    x += (2.0 * floatsin(-a, degrees));
			y += (2.0 * floatcos(-a, degrees));
			CopObjectData[id][ObjX] = x;
			CopObjectData[id][ObjY] = y;
			CopObjectData[id][ObjZ] = z;
			CopObjectData[id][ObjRX] = 0.0;
			CopObjectData[id][ObjRY] = 0.0;
			CopObjectData[id][ObjRZ] = a;
			CopObjectData[id][ObjID] = CreateDynamicObject(19834, x, y, z, 0.0, 0.0, a, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
			CopObjectData[id][ObjArea] = -1;
			
			new string[96];
			format(string, sizeof(string), "Police Line (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
			CopObjectData[id][ObjLabel] = CreateDynamic3DTextLabel(string, 0x3498DBFF, x, y, z + 0.35, 5.0, _, _, _, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
            InsertObjectToDB(id);
		}
		
		if(listitem == 3)
		{
		    new id = GetFreeObjectID();
		    if(id == -1) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Cop object limit reached.");
		    CopObjectData[id][ObjCreated] = true;
		    GetPlayerName(playerid, CopObjectData[id][Owner], MAX_PLAYER_NAME);
		    CopObjectData[id][Type] = OBJECT_TYPE_SPIKE;
		    CopObjectData[id][ObjModel] = 2899;
		    CopObjectData[id][ObjInterior] = GetPlayerInterior(playerid);
		    CopObjectData[id][ObjVirtualWorld] = GetPlayerVirtualWorld(playerid);

		    new Float: x, Float: y, Float: z, Float: a;
		    GetPlayerPos(playerid, x, y, z);
		    GetPlayerFacingAngle(playerid, a);
		    x += (2.0 * floatsin(-a, degrees));
			y += (2.0 * floatcos(-a, degrees));
			
			CopObjectData[id][ObjX] = x;
			CopObjectData[id][ObjY] = y;
			CopObjectData[id][ObjZ] = z - 0.85;
			CopObjectData[id][ObjRX] = 0.0;
			CopObjectData[id][ObjRY] = 0.0;
			CopObjectData[id][ObjRZ] = a + 90.0;
			CopObjectData[id][ObjID] = CreateDynamicObject(2899, x, y, z - 0.85, 0.0, 0.0, a + 90.0, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
			CopObjectData[id][ObjArea] = CreateDynamicSphere(x, y, z - 0.85, 2.5, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
            
			new string[96];
			format(string, sizeof(string), "Spike Strip (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
			CopObjectData[id][ObjLabel] = CreateDynamic3DTextLabel(string, 0x3498DBFF, x, y, z - 0.4, 3.0, _, _, _, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
            InsertObjectToDB(id);
		}
		
		if(listitem == 4) ShowPlayerDialog(playerid, COPOBJECTS_DIALOG+1, DIALOG_STYLE_INPUT, "Speed Camera Setup", "Write a speed limit for this speed camera:", "Create", "Cancel");
	    return 1;
	}
	
	if(dialogid == COPOBJECTS_DIALOG+1)
	{
		if(!response) return 1;
		if(!strlen(inputtext)) return ShowPlayerDialog(playerid, COPOBJECTS_DIALOG+1, DIALOG_STYLE_INPUT, "Speed Camera Setup", "Write a speed limit for this speed camera:", "Create", "Cancel");
		new id = GetFreeObjectID(), limit = strval(inputtext);
	    if(id == -1) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Cop object limit reached.");
	    CopObjectData[id][ObjCreated] = true;
	    GetPlayerName(playerid, CopObjectData[id][Owner], MAX_PLAYER_NAME);
	    CopObjectData[id][Type] = OBJECT_TYPE_SPEEDCAM;
	    CopObjectData[id][ObjData] = limit;
	    CopObjectData[id][ObjModel] = 18880;
	    CopObjectData[id][ObjInterior] = GetPlayerInterior(playerid);
	    CopObjectData[id][ObjVirtualWorld] = GetPlayerVirtualWorld(playerid);

	    new Float: x, Float: y, Float: z, Float: a;
	    GetPlayerPos(playerid, x, y, z);
	    GetPlayerFacingAngle(playerid, a);
	    x += (2.0 * floatsin(-a, degrees));
		y += (2.0 * floatcos(-a, degrees));
		CopObjectData[id][ObjX] = x;
		CopObjectData[id][ObjY] = y;
		CopObjectData[id][ObjZ] = z - 1.5;
		CopObjectData[id][ObjRX] = 0.0;
		CopObjectData[id][ObjRY] = 0.0;
		CopObjectData[id][ObjRZ] = 0.0;
		CopObjectData[id][ObjID] = CreateDynamicObject(18880, x, y, z - 1.5, 0.0, 0.0, 0.0, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
		CopObjectData[id][ObjArea] = CreateDynamicSphere(x, y, z - 1.5, SPEEDCAM_RANGE, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
		
		new string[128];
		format(string, sizeof(string), "Speed Camera (ID: %d)\n{FFFFFF}Speed Limit: {E74C3C}%d\n{FFFFFF}Placed by %s", id, limit, CopObjectData[id][Owner]);
		CopObjectData[id][ObjLabel] = CreateDynamic3DTextLabel(string, 0x3498DBFF, x, y, z + 3.85, SPEEDCAM_RANGE, _, _, _, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
        InsertObjectToDB(id);
		return 1;
	}
	
	return 0;
}

public OnPlayerModelSelection(playerid, response, listid, modelid)
{
	if(listid == RoadblockList)
	{
	    if(!response) return 1;
		new id = GetFreeObjectID();
	    if(id == -1) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Cop object limit reached.");
	    CopObjectData[id][ObjCreated] = true;
	    GetPlayerName(playerid, CopObjectData[id][Owner], MAX_PLAYER_NAME);
	    CopObjectData[id][Type] = OBJECT_TYPE_ROADBLOCK;
	    CopObjectData[id][ObjModel] = modelid;
	    CopObjectData[id][ObjInterior] = GetPlayerInterior(playerid);
	    CopObjectData[id][ObjVirtualWorld] = GetPlayerVirtualWorld(playerid);

	    new Float: x, Float: y, Float: z, Float: a;
	    GetPlayerPos(playerid, x, y, z);
	    GetPlayerFacingAngle(playerid, a);
	    x += (2.0 * floatsin(-a, degrees));
		y += (2.0 * floatcos(-a, degrees));
		CopObjectData[id][ObjX] = x;
		CopObjectData[id][ObjY] = y;
		CopObjectData[id][ObjZ] = z;
		CopObjectData[id][ObjRX] = 0.0;
		CopObjectData[id][ObjRY] = 0.0;
		CopObjectData[id][ObjRZ] = a;
		CopObjectData[id][ObjID] = CreateDynamicObject(modelid, x, y, z, 0.0, 0.0, a, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
		CopObjectData[id][ObjArea] = -1;

		new string[96];
		format(string, sizeof(string), "Roadblock (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
		CopObjectData[id][ObjLabel] = CreateDynamic3DTextLabel(string, 0x3498DBFF, x, y, z + 1.35, 10.0, _, _, _, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
		InsertObjectToDB(id);
	}
	
	if(listid == SignList)
	{
	    if(!response) return 1;
		new id = GetFreeObjectID();
	    if(id == -1) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Cop object limit reached.");
	    CopObjectData[id][ObjCreated] = true;
	    GetPlayerName(playerid, CopObjectData[id][Owner], MAX_PLAYER_NAME);
	    CopObjectData[id][Type] = OBJECT_TYPE_SIGN;
	    CopObjectData[id][ObjModel] = modelid;
	    CopObjectData[id][ObjInterior] = GetPlayerInterior(playerid);
	    CopObjectData[id][ObjVirtualWorld] = GetPlayerVirtualWorld(playerid);

	    new Float: x, Float: y, Float: z, Float: a;
	    GetPlayerPos(playerid, x, y, z);
	    GetPlayerFacingAngle(playerid, a);
	    x += (2.0 * floatsin(-a, degrees));
		y += (2.0 * floatcos(-a, degrees));
		CopObjectData[id][ObjX] = x;
		CopObjectData[id][ObjY] = y;
		CopObjectData[id][ObjZ] = z - 1.25;
		CopObjectData[id][ObjRX] = 0.0;
		CopObjectData[id][ObjRY] = 0.0;
		CopObjectData[id][ObjRZ] = a;
		CopObjectData[id][ObjID] = CreateDynamicObject(modelid, x, y, z - 1.25, 0.0, 0.0, a, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
		CopObjectData[id][ObjArea] = -1;

		new string[96];
		format(string, sizeof(string), "Sign (ID: %d)\n{FFFFFF}Placed by %s", id, CopObjectData[id][Owner]);
		CopObjectData[id][ObjLabel] = CreateDynamic3DTextLabel(string, 0x3498DBFF, x, y, z + 2.0, 10.0, _, _, _, CopObjectData[id][ObjVirtualWorld], CopObjectData[id][ObjInterior]);
		InsertObjectToDB(id);
	}
	
	return 1;
}

public OnPlayerEnterDynamicArea(playerid, areaid)
{
	if(GetPlayerState(playerid) == PLAYER_STATE_DRIVER)
	{
		for(new i; i < MAX_COP_OBJECTS; i++)
		{
		    if(!CopObjectData[i][ObjCreated]) continue;
		    if(areaid == CopObjectData[i][ObjArea])
		    {
				switch(CopObjectData[i][Type])
				{
				    case OBJECT_TYPE_SPIKE:
				    {
						new panels, doors, lights, tires;
			        	GetVehicleDamageStatus(GetPlayerVehicleID(playerid), panels, doors, lights, tires);
			        	UpdateVehicleDamageStatus(GetPlayerVehicleID(playerid), panels, doors, lights, encode_tires(1, 1, 1, 1));
			        	PlayerPlaySound(playerid, 1190, 0.0, 0.0, 0.0);
					}

					case OBJECT_TYPE_SPEEDCAM:
					{
					    new speed = GetPlayerSpeed(playerid);
					    if(speed > CopObjectData[i][ObjData])
					    {
					        // detected by a speed camera
					        PlayerPlaySound(playerid, 1132, 0.0, 0.0, 0.0);
					        new name[MAX_PLAYER_NAME]; GetPlayerName(playerid, name, MAX_PLAYER_NAME);
					        new tempstr[256];
					        format(tempstr, 256, "[SpeedCam] player %s (%d) just passed speed camera #(%d) with %dkm/h speed!", name, playerid, i, speed);
					        SendRadioMessage(tempstr);
					        format(tempstr, 256, "[SpeedCam] you just passed a speed camera with %dkm/h speed", speed);
					        SendClientMessage(playerid, -1, tempstr);
					        SendClientMessage(playerid, -1, "your action reported to online cops");
					    }
					}
				}

				break;
		    }
		}
	}
	
	return 1;
}

public OnPlayerEditDynamicObject(playerid, objectid, response, Float:x, Float:y, Float:z, Float:rx, Float:ry, Float:rz)
{
	if(EditingCopObjectID[playerid] != -1)
	{
	    new id = EditingCopObjectID[playerid];

	    switch(response)
	    {
			case EDIT_RESPONSE_FINAL:
			{
			    CopObjectData[id][ObjX] = x;
				CopObjectData[id][ObjY] = y;
				CopObjectData[id][ObjZ] = z;
				CopObjectData[id][ObjRX] = rx;
				CopObjectData[id][ObjRY] = ry;
				CopObjectData[id][ObjRZ] = rz;
			    SetDynamicObjectPos(objectid, x, y, z);
	            SetDynamicObjectRot(objectid, rx, ry, rz);
	            
	            Streamer_SetFloatData(STREAMER_TYPE_3D_TEXT_LABEL, CopObjectData[id][ObjLabel], E_STREAMER_X, x);
	            Streamer_SetFloatData(STREAMER_TYPE_3D_TEXT_LABEL, CopObjectData[id][ObjLabel], E_STREAMER_Y, y);
	            Streamer_SetFloatData(STREAMER_TYPE_3D_TEXT_LABEL, CopObjectData[id][ObjLabel], E_STREAMER_Z, z + zOffsets[ CopObjectData[id][Type] ]);
	            
	            if(IsValidDynamicArea(CopObjectData[id][ObjArea]))
	            {
	                Streamer_SetFloatData(STREAMER_TYPE_AREA, CopObjectData[id][ObjArea], E_STREAMER_X, x);
		            Streamer_SetFloatData(STREAMER_TYPE_AREA, CopObjectData[id][ObjArea], E_STREAMER_Y, y);
		            Streamer_SetFloatData(STREAMER_TYPE_AREA, CopObjectData[id][ObjArea], E_STREAMER_Z, z + zOffsets[ CopObjectData[id][Type] ]);
	            }

				SaveObjectToDB(id);
			    EditingCopObjectID[playerid] = -1;
			}
			
	        case EDIT_RESPONSE_CANCEL:
	        {
	            SetDynamicObjectPos(objectid, CopObjectData[id][ObjX], CopObjectData[id][ObjY], CopObjectData[id][ObjZ]);
	            SetDynamicObjectRot(objectid, CopObjectData[id][ObjRX], CopObjectData[id][ObjRY], CopObjectData[id][ObjRZ]);
	            EditingCopObjectID[playerid] = -1;
	        }
	    }
	}
	
	return 1;
}

CMD:placeobject(playerid, params[])
{
 	if(!IsACop(playerid)) {
 		return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Only cops can use this command.");
 	}
 	if(IsPlayerInAnyVehicle(playerid)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}You can't use this command in a vehicle.");
 	ShowPlayerDialog(playerid, COPOBJECTS_DIALOG, DIALOG_STYLE_LIST, "Cop Objects: Choose Category", "Roadblocks\nSigns\nPolice Line\nSpike Strip\nSpeed Camera", "Choose", "Cancel");
	return 1;
}

CMD:editobject(playerid, params[])
{
    if(!IsAdmin(playerid) && !IsACop(playerid)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Only cops can use this command.");
	if(EditingCopObjectID[playerid] != -1) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}You're already editing an object.");
	if(isnull(params)) return SendClientMessage(playerid, 0xF39C12FF, "USAGE: {FFFFFF}/editobject [id]");
	new id = strval(params[0]);
	if(!(0 <= id <= MAX_COP_OBJECTS - 1)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Invalid object ID.");
	if(!CopObjectData[id][ObjCreated]) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Object doesn't exist.");
	if(!IsPlayerInRangeOfPoint(playerid, 16.0, CopObjectData[id][ObjX], CopObjectData[id][ObjY], CopObjectData[id][ObjZ])) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}You're not near the object you want to edit.");
	new name[MAX_PLAYER_NAME];
	GetPlayerName(playerid, name, MAX_PLAYER_NAME);
	if(!IsAdmin(playerid) && strcmp(CopObjectData[id][Owner], name)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}This object isn't yours, you can't edit it.");
    EditingCopObjectID[playerid] = id;
	EditDynamicObject(playerid, CopObjectData[id][ObjID]);
	return 1;
}

CMD:gotoobject(playerid, params[])
{
	if(!IsAdmin(playerid)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Only RCON admins can use this command.");
	if(isnull(params)) return SendClientMessage(playerid, 0xF39C12FF, "USAGE: {FFFFFF}/gotoobject [id]");
	new id = strval(params[0]);
	if(!(0 <= id <= MAX_COP_OBJECTS - 1)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Invalid object ID.");
	if(!CopObjectData[id][ObjCreated]) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Object doesn't exist.");
	SetPlayerPos(playerid, CopObjectData[id][ObjX], CopObjectData[id][ObjY], CopObjectData[id][ObjZ] + 1.75);
	SetPlayerInterior(playerid, CopObjectData[id][ObjInterior]);
	SetPlayerVirtualWorld(playerid, CopObjectData[id][ObjVirtualWorld]);
	SendClientMessage(playerid, -1, "Teleported to object.");
	return 1;
}

CMD:removeobject(playerid, params[])
{
    if(!IsAdmin(playerid) && !IsACop(playerid)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Only cops can use this command.");
	if(isnull(params)) return SendClientMessage(playerid, 0xF39C12FF, "USAGE: {FFFFFF}/editobject [id]");
	new id = strval(params[0]);
	if(!(0 <= id <= MAX_COP_OBJECTS - 1)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Invalid object ID.");
	if(!CopObjectData[id][ObjCreated]) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}Object doesn't exist.");
	if(EditingCopObjectID[playerid] == id) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}You can't remove an object you're editing.");
	new name[MAX_PLAYER_NAME];
	GetPlayerName(playerid, name, MAX_PLAYER_NAME);
	if(!IsAdmin(playerid) && strcmp(CopObjectData[id][Owner], name)) return SendClientMessage(playerid, 0xE74C3CFF, "ERROR: {FFFFFF}This object isn't yours, you can't remove it.");
	CopObjectData[id][ObjCreated] = false;
	DestroyDynamicObject(CopObjectData[id][ObjID]);
	DestroyDynamic3DTextLabel(CopObjectData[id][ObjLabel]);
	if(IsValidDynamicArea(CopObjectData[id][ObjArea])) DestroyDynamicArea(CopObjectData[id][ObjArea]);
	CopObjectData[id][ObjID] = -1;
	CopObjectData[id][ObjLabel] = Text3D: -1;
	CopObjectData[id][ObjArea] = -1;
	stmt_bind_value(RemoveObject, 0, DB::TYPE_INTEGER, id);
	stmt_execute(RemoveObject);
	
	SendClientMessage(playerid, -1, "Object removed.");
	return 1;
}
