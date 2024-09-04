# Preface

I am a systems administrator for the Atlas College in the Netherlands. Atlas College is a VO school (High School?) which uses MS Teams for teaching purposes.
One of my responsibilities as a system administrator for the Atlas College in Hoorn is facilitating the educational teams (EduTeams) for our classes. We started doing that by using MS School Data Sync (SDS) back 2018. Our School Information System (SIS) being Magister we lacked a direct coupling with SDS. So I wrote an interface between our SIS and SDS using Perl.
With SDS 2.0 at the horizon we evaluated this coupling, which broke due to changes in the SIS, and decided to not upgrade this coupling for SDS 2.0. Companies delivering Identity Management Systems (IDM) promise us they can take over. But remarks as “can we is Graph to do this” does not fill me with confidence. Suits in companies like that tend to promise a lot to make a sale, and leave the implementation to the techies.
So I decided to investigate the possibility of facilitating EduTeams myself. And I found that it’s indeed possible, but not straightforward. In this document I would like to go deeper into the process of creating educational teams with MS Graph and the implications of the different methos at hand.
If interested in my code It can be found on GitHub. No guaranties are given as to its workings, it’s verry much work in progress.

# Assumptions made

I do assume the reader is capable of making Graph request, is aware of the process of App registration in Azure to do such things. MS has done quite a nice job of documenting their APIs and has been the major source of this documentation.
Allthough I use Perl to write these interfaces this I by no means the only way. In fact I think I’m kind of a loner in doing it that way. Your toolchain could be NodeJS, Poweshell or whatever. It does not really matter

# A birds eye view of an EduTeam

At first glance an EduTeam is just like any other team. But when you take a better look you notice some important differences. They are facilitated with all kinds of goodies to act as a place in which you can teach. Most noticeable:
- Hidden for students by default, teacher can “activate” the team.
- They have a classnotebook.
- Can have assignments.
- Which in turn can have rubrics.
- And more

EduTeams are created using a special template, “EducationClass”, and are only available in educational tenants.

# Creating an EduTeam

You would presume that the method of creating a group and transforming it into a team would work. This is in fact the case for “normal” teams, not so for EduTeams.
To use the EducationalClass template the group has to be associated with a class. So instead of creating a group you should create a class. By creating a class the associated (unified) group is created automatically. Both the class and the group share the same identity.
After the group has been created has been created (background processes can take up to 15 minutes) using the CreateClass method you can transform it into a EduTeam by using the EducationalClass template.

# Adding members and owners

## Using the group methods

Teams being specialized groups gives the possibility of using the more standard group methods of adding users. But there are drawbacks to this method.
The first thing to take into account is that an owners should also be a member of a team. When using the groups methods you must add an owner both as owner and member. Resulting in two separate transactions.
Next there are the delays which are in effect:
-	A member added to a group will be visible as a team member within the next 24 hours.
-	The member/owner is only added to the team if on of its members has been active in Teams (not in the mobile app).

The thing that made me look further is the limits on members which can be added per transaction:  20. In my organization 20 members would suffice for normal teams, but not for classes. Classes are almost always larger than 20 members. We  also facilitate cross section teams (teams in instance for all students of a certain course or grade level) which can easily have hundredth members or more.
Of course you can work around this. You can add members In a loop, add them in batches of 20, you can even use batched JSON (which in fact also imposes a limit of 20 on the number of elements in the batch) to add them. But the result is a lot of transactions and complex coding.

## Using the teams methods

Analog to the Groups API methods the Teams API gives you method to add users. An important difference is that users are added to the team with a role. That way you are able to add an owner in one single transaction. These methods also impose the 20 users limit per transaction. But read on…
I guess the guys who programmed the recognized the fact that adding 20 users to a team is not a whole lot. Not sure as to the reason, but there is a method [add users in batch](https://learn.microsoft.com/en-us/graph/api/conversationmembers-add?view=graph-rest-1.0&tabs=http). And that method can add up to 200 users in one transaction. This suffices for the majority of the teams I need to create. Only a fraction of the teams we facilitate will be larger than that.

## Conclusion: Propossed workflow

To conclude I would like to propose the following method for creating educational teams:
- Create a class using the educational Graph API
- Wait 15 minutes for background processing.
- [Add members](https://learn.microsoft.com/en-us/graph/api/conversationmembers-add?view=graph-rest-1.0&tabs=http) with roles using the Teams Graph API


